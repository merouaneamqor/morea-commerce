# frozen_string_literal: true

module Orders
  # Staff create / edit / duplicate for the admin order desk (storefront still uses Checkout).
  class Editor
    class Error < StandardError; end

    # ActiveModel::Errors#full_messages asks its owner for human attribute names; without this an error on a
    # field (an invalid phone, say) raised NoMethodError instead of showing the message.
    extend ActiveModel::Translation

    attr_reader :store, :user, :order, :errors

    def initialize(store:, user: nil, external_effects: true)
      @store = store
      @user = user
      @external_effects = external_effects
      @errors = ActiveModel::Errors.new(self)
    end

    def create(attrs)
      @order = nil
      lines = normalize_lines(attrs[:lines])
      contact = normalize_contact(attrs)
      return failure unless valid_for_write?(contact, lines, attrs)

      agent = assignable_agent(attrs[:agent_id])
      if attrs[:agent_id].present? && agent.nil?
        errors.add(:base, "Choose an active confirmation agent of this store.")
        return failure
      end

      ActiveRecord::Base.transaction do
        customer = find_or_create_customer!(contact)
        totals = compute_totals(lines, attrs)

        # Never assigned to the person who typed the order: it waits in "Available now"
        # unless an agent was picked explicitly.
        @order = store.orders.create!(
          skip_auto_whatsapp: true,
          customer: customer,
          customer_name: contact[:name],
          customer_phone: contact[:phone],
          customer_city: contact[:city],
          customer_district: contact[:district],
          customer_address: contact[:address],
          second_phone: contact[:second_phone],
          notes: attrs[:notes].presence,
          tags: normalize_tags(attrs[:tags]),
          payment_method: "cod",
          status: "new",
          currency: store.currency,
          **totals,
          **delivery_attributes(attrs),
          **sendit_district_for(contact)
        )

        write_lines!(@order, lines)
        customer.increment!(:orders_count)
        @order.record_event!("created", body: "Order created by staff", user: user)
        if agent
          OrderConfirmation.create!(store: store, order: @order, assigned_user: agent, claimed_at: Time.current)
          @order.record_event!("comment", body: "Assigned to #{agent.name.presence || agent.email} at creation", user: user)
        end
      end

      if @external_effects
        OrderStatusJob.perform_later(@order.id)
        DiscordOrderNotifyJob.perform_later(@order.id)
        NewOrderAlertJob.perform_later(@order.id)
      end
      success(@order)
    rescue ActiveRecord::RecordInvalid => e
      errors.add(:base, e.record.errors.full_messages.to_sentence.presence || e.message)
      failure
    end

    def update(order, attrs)
      @order = order
      raise Error, order.edit_lock_reason unless order.editable?

      lines = normalize_lines(attrs[:lines])
      contact = normalize_contact(attrs)
      return failure unless valid_for_write?(contact, lines, attrs)

      ActiveRecord::Base.transaction do
        previous_customer = order.customer
        previous_lines = snapshot_lines(order)

        customer = find_or_create_customer!(contact)
        totals = compute_totals(lines, attrs)

        if order.inventory_reserved?
          apply_inventory_delta!(order, previous_lines, lines)
        end

        order.order_items.destroy_all
        write_lines!(order, lines)

        order.update!(
          customer: customer,
          customer_name: contact[:name],
          customer_phone: contact[:phone],
          customer_city: contact[:city],
          customer_district: contact[:district],
          customer_address: contact[:address],
          second_phone: attrs.key?(:second_phone) ? contact[:second_phone] : order.second_phone,
          **delivery_attributes(attrs, current: order),
          notes: attrs.key?(:notes) ? attrs[:notes].presence : order.notes,
          tags: attrs.key?(:tags) ? normalize_tags(attrs[:tags]) : order.tags,
          **totals,
          **sendit_district_for(contact)
        )

        if previous_customer.id != customer.id
          previous_customer.decrement!(:orders_count) if previous_customer.orders_count.positive?
          customer.increment!(:orders_count)
        end

        order.record_event!("edited", body: "Order details updated", user: user)
      end

      sync_sendit_after_edit!(order.reload)
      success(order)
    rescue Error => e
      errors.add(:base, e.message)
      failure
    rescue ActiveRecord::RecordInvalid => e
      errors.add(:base, e.record.errors.full_messages.to_sentence.presence || e.message)
      failure
    rescue StandardError => e
      errors.add(:base, e.message)
      failure
    end

    def duplicate(order)
      if order.external_order_receipt.present?
        errors.add(:base, I18n.t("connections.external_order_locked"))
        return failure
      end

      attrs = {
        name: order.customer_name,
        phone: order.customer_phone,
        city: order.customer_city,
        district: order.customer_district,
        address: order.customer_address,
        notes: order.notes,
        tags: order.tags,
        shipping_dh: order.shipping_cents.to_i / 100.0,
        discount_code: order.discount_code,
        discount_dh: order.discount_code.blank? ? (order.discount_cents.to_i / 100.0) : nil,
        lines: order.order_items.map { |item|
          {
            product_id: item.product_id,
            product_variant_id: item.product_variant_id,
            quantity: item.quantity
          }
        }
      }

      result = create(attrs)
      return result unless result

      result.record_event!("duplicated", body: "Duplicated from ##{order.number}", user: user)
      result
    end

    def update_tags(order, tags)
      order.update!(tags: normalize_tags(tags))
      order.record_event!("edited", body: "Tags updated", user: user)
      success(order)
    end

    def add_comment(order, body)
      text = body.to_s.strip
      if text.blank?
        errors.add(:base, "Comment cannot be blank.")
        return failure
      end

      order.record_event!("comment", body: text, user: user)
      success(order)
    end

    private

    def success(order)
      order
    end

    def failure
      false
    end

    def normalize_contact(attrs)
      {
        name: attrs[:name].to_s.strip,
        phone: attrs[:phone].to_s.strip,
        second_phone: attrs[:second_phone].to_s.strip.presence,
        phone_country: attrs[:phone_country].presence || "MA",
        city: attrs[:city].to_s.strip,
        district: attrs[:district].to_s.strip.presence,
        address: attrs[:address].to_s.strip
      }
    end

    def normalize_lines(raw)
      list = raw
      list = list.values if list.respond_to?(:values) && !list.is_a?(Array)
      Array(list).filter_map do |line|
        next unless line.respond_to?(:to_h) || line.is_a?(Hash)

        h = line.respond_to?(:to_unsafe_h) ? line.to_unsafe_h : line.to_h
        h = h.with_indifferent_access
        qty = h[:quantity].to_i
        next if qty <= 0
        next if h[:product_id].blank?

        {
          product_id: h[:product_id].to_i,
          product_variant_id: h[:product_variant_id].presence&.to_i,
          quantity: qty
        }
      end
    end

    def normalize_tags(value)
      list = case value
      when Array then value
      else value.to_s.split(",")
      end
      list.map { |t| t.to_s.strip.downcase }.compact_blank.uniq.join(", ").presence
    end

    def valid_for_write?(contact, lines, attrs)
      errors.clear
      %i[name phone city address].each do |field|
        errors.add(field, "can't be blank") if contact[field].blank?
      end

      phone = Checkout.normalize_phone(contact[:phone], country: contact[:phone_country])
      errors.add(:phone, "is invalid") if contact[:phone].present? && phone.blank?
      contact[:phone] = phone if phone.present?

      if contact[:second_phone]
        second = Checkout.normalize_phone(contact[:second_phone], country: contact[:phone_country])
        errors.add(:second_phone, "is invalid") if second.blank?
        contact[:second_phone] = second
      end

      errors.add(:base, "Add at least one product.") if lines.empty?

      lines.each do |line|
        product = store.products.find_by(id: line[:product_id])
        unless product
          errors.add(:base, "Unknown product ##{line[:product_id]}")
          next
        end

        if line[:product_variant_id].present?
          variant = product.product_variants.find_by(id: line[:product_variant_id])
          errors.add(:base, "Unknown variant for #{product.name}") unless variant
        end
      end

      if attrs[:discount_code].present?
        code = attrs[:discount_code].to_s.strip.upcase
        discount = store.discounts.current.find_by(code: code)
        errors.add(:discount_code, "is not valid") unless discount
      end

      if errors.empty?
        total = compute_totals(lines, attrs)[:total_cents]
        errors.add(:base, "The order total must be above 0 #{store.currency}.") if total.zero?
        validate_delivery_details(attrs, total)
      end

      errors.empty?
    end

    # The delivery company, the wished day and the advance typed with the order. On an update only the keys given are written.
    def delivery_attributes(attrs, current: nil)
      result = {}
      result[:delivery_provider] = attrs[:delivery_provider].to_s.strip.presence if current.nil? || attrs.key?(:delivery_provider)
      result[:scheduled_for] = parse_schedule(attrs[:scheduled_for]) if current.nil? || attrs.key?(:scheduled_for)
      result[:advance_cents] = advance_cents(attrs[:advance_dh]) if current.nil? || attrs.key?(:advance_dh)
      result
    end

    def parse_schedule(value)
      return if value.blank?

      ActiveSupport::TimeZone[DateRange::ZONE].parse(value.to_s)
    rescue ArgumentError
      nil
    end

    # "50" or "50,5" MAD to whole centimes; never negative.
    def advance_cents(value)
      return 0 if value.blank?

      [ (BigDecimal(value.to_s.tr(",", ".")) * 100).round(0).to_i, 0 ].max
    rescue ArgumentError
      0
    end

    # Only a delivery company the store is connected to through its API can be chosen; the wished day must be a real date;
    # the advance cannot be more than the order's total.
    def validate_delivery_details(attrs, total)
      provider = attrs[:delivery_provider].to_s.strip
      if provider.present? && !connected_providers.include?(provider)
        errors.add(:delivery_provider, "must be a delivery company this store is connected to")
      end
      if attrs[:scheduled_for].present? && parse_schedule(attrs[:scheduled_for]).nil?
        errors.add(:scheduled_for, "is not a valid date")
      end
      if attrs[:advance_dh].present?
        begin
          errors.add(:base, "The advance cannot be negative.") if BigDecimal(attrs[:advance_dh].to_s.tr(",", ".")).negative?
        rescue ArgumentError
          errors.add(:base, "The advance must be an amount.")
        end
        errors.add(:base, "The advance cannot be more than the total of the order.") if advance_cents(attrs[:advance_dh]) > total
      end
    end

    def connected_providers
      @connected_providers ||= store.delivery_accounts.where(is_active: true).where.not(connected_at: nil).pluck(:provider).uniq
    end

    # The optional "Assign to agent" choice: only an active confirmation agent of this store.
    def assignable_agent(agent_id)
      return if agent_id.blank?

      store.users.active.where(confirmation_role: "agent").find_by(id: agent_id)
    end

    def find_or_create_customer!(contact)
      Customer.find_or_create_from_checkout!(
        store: store,
        name: contact[:name],
        phone: contact[:phone],
        city: contact[:city],
        district: contact[:district],
        address: contact[:address]
      )
    end

    def resolve_line_pricing(line)
      product = store.products.find(line[:product_id])
      variant = line[:product_variant_id].present? ? product.product_variants.find(line[:product_variant_id]) : nil
      unit = variant&.unit_price_cents || product.price_cents
      {
        product: product,
        product_variant: variant,
        product_name: product.name,
        variant_name: variant&.display_name,
        quantity: line[:quantity],
        unit_price_cents: unit,
        total_cents: unit * line[:quantity]
      }
    end

    def compute_totals(lines, attrs)
      priced = lines.map { |l| resolve_line_pricing(l) }
      subtotal = priced.sum { |l| l[:total_cents] }

      discount_cents = 0
      discount_code = nil
      if attrs[:discount_code].present?
        discount = store.discounts.current.find_by(code: attrs[:discount_code].to_s.strip.upcase)
        if discount
          discount_cents = discount.amount_for(subtotal)
          discount_code = discount.code
        end
      elsif attrs[:discount_dh].present?
        discount_cents = [ (attrs[:discount_dh].to_f * 100).round, subtotal ].min
        discount_cents = 0 if discount_cents.negative?
      end

      shipping_cents = if ActiveModel::Type::Boolean.new.cast(attrs[:shipping_excluded])
        0   # "Exclus": the customer pays the products only
      elsif attrs.key?(:shipping_dh)
        [ (attrs[:shipping_dh].to_f * 100).round, 0 ].max
      else
        0
      end

      {
        subtotal_cents: subtotal,
        discount_cents: discount_cents,
        discount_code: discount_code,
        shipping_cents: shipping_cents,
        total_cents: [ subtotal - discount_cents + shipping_cents, 0 ].max
      }
    end

    def write_lines!(order, lines)
      lines.each do |line|
        priced = resolve_line_pricing(line)
        order.order_items.create!(
          product: priced[:product],
          product_variant: priced[:product_variant],
          product_name: priced[:product_name],
          variant_name: priced[:variant_name],
          quantity: priced[:quantity],
          unit_price_cents: priced[:unit_price_cents],
          unit_cost_cents: priced[:product].cost_cents,
          total_cents: priced[:total_cents]
        )
      end
    end

    def snapshot_lines(order)
      order.order_items.map do |item|
        {
          product_id: item.product_id,
          product_variant_id: item.product_variant_id,
          quantity: item.quantity,
          product: item.product,
          product_variant: item.product_variant,
          product_name: item.product_name
        }
      end
    end

    # Keyed by product + variant; positive qty means more reserved, negative means restored
    def apply_inventory_delta!(order, previous_lines, new_lines)
      previous = Hash.new(0)
      previous_meta = {}
      previous_lines.each do |line|
        key = [ line[:product_id], line[:product_variant_id] ]
        previous[key] += line[:quantity]
        previous_meta[key] = line
      end

      desired = Hash.new(0)
      new_lines.each do |line|
        key = [ line[:product_id], line[:product_variant_id] ]
        desired[key] += line[:quantity]
      end

      (previous.keys | desired.keys).each do |key|
        delta = desired[key] - previous[key]
        next if delta.zero?

        product = store.products.find(key[0])
        next unless product.track_inventory

        variant = key[1].present? ? product.product_variants.find(key[1]) : nil

        begin
          Inventory::Adjuster.adjust!(
            product: product,
            variant: variant,
            quantity: -delta,
            reason: "order_edited",
            note: "Order #{order.number}",
            order: order
          )
        rescue Inventory::Adjuster::Error => e
          raise Error, "Insufficient stock for #{product.name}" if e.message.include?("below zero")

          raise Error, e.message
        end
      end
    end

    def sendit_district_for(contact)
      return {} unless @external_effects

      return {} unless Sendit::Client.configured?(store)

      match = if contact[:district].present?
        Sendit::Districts.match(store: store, city: contact[:city], address: contact[:district])
      else
        Sendit::Districts.match(store: store, city: contact[:city], address: contact[:address].to_s)
      end
      match ? { sendit_district_id: match[:id], sendit_district_name: match[:name] } : {}
    rescue StandardError => e
      Rails.logger.warn("[Orders::Editor] Sendit district match failed: #{e.message}")
      {}
    end

    def sync_sendit_after_edit!(order)
      return if order.sendit_code.blank?
      return unless Sendit::Sync.new(order).cancellable?

      Sendit::Sync.new(order).update!
    rescue StandardError => e
      Rails.logger.warn("[Orders::Editor] Sendit update failed for #{order.number}: #{e.message}")
    end
  end
end
