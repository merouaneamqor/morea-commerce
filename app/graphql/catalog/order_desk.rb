# frozen_string_literal: true

module Catalog
  module OrderDesk
    class Error < StandardError; end

    ACTIONS = %w[create update duplicate transition archive unarchive tags comment shipment].freeze
    EDIT_FIELDS = %w[name phone phoneCountry city district address notes tags shippingDh discountDh discountCode lines].freeze
    module_function

    def find(store, number)
      store.orders.find_by!(number: number.to_s.strip)
    rescue ActiveRecord::RecordNotFound
      raise Error, "Order not found in this store."
    end

    def details(store, number:, include_contact: false)
      order = find(store, number)
      result = present(order)
      events = order.order_events.order(created_at: :desc, id: :desc).limit(100)
      result.merge!("events" => events.map { |event| { "kind" => event.kind, "body" => event.body, "createdAt" => event.created_at.iso8601 } },
        "eventsTruncated" => order.order_events.count > 100)
      if include_contact
        result["shipTo"] = { "name" => order.customer_name, "phone" => order.customer_phone,
          "city" => order.customer_city, "district" => order.customer_district, "address" => order.customer_address }
      end
      result
    end

    def perform(store, action:, number: nil, attrs: {}, confirm: false)
      raise Error, "Unknown order action." unless ACTIONS.include?(action)
      raise Error, "Set confirm: true to change an order." unless confirm == true
      raise Error, "attrs must be an object." unless attrs.is_a?(Hash)

      attrs = attrs.deep_stringify_keys
      editor = Orders::Editor.new(store: store)
      if action == "create"
        order = editor.create(editor_attrs(store, attrs))
        raise Error, editor.errors.full_messages.to_sentence unless order
      else
        order = find(store, number)
        order.with_lock do
          case action
          when "update"
            raise Error, editor.errors.full_messages.to_sentence unless editor.update(order, editor_attrs(store, attrs, order: order))
          when "duplicate"
            reject_unknown!(attrs, [])
            copy = editor.duplicate(order)
            raise Error, editor.errors.full_messages.to_sentence unless copy

            order = copy
          when "transition"
            reject_unknown!(attrs, %w[status reason])
            raise Error, "Use cancel_order to cancel an order." if attrs["status"] == "cancelled"

            transition!(order, attrs)
          when "archive", "unarchive"
            reject_unknown!(attrs, [])
            action == "archive" ? order.archive! : order.unarchive!
          when "tags"
            reject_unknown!(attrs, %w[tags])
            raise Error, "tags must be an array of strings." unless attrs["tags"].is_a?(Array) && attrs["tags"].all? { |tag| tag.is_a?(String) }

            editor.update_tags(order, attrs["tags"])
          when "comment"
            reject_unknown!(attrs, %w[body])
            raise Error, "Comment must be 1-10000 characters." unless attrs["body"].is_a?(String) && attrs["body"].strip.length.between?(1, 10_000)
            raise Error, editor.errors.full_messages.to_sentence unless editor.add_comment(order, attrs["body"])
          when "shipment"
            reject_unknown!(attrs, %w[operation])
            shipment!(store, order, attrs.fetch("operation"))
          end
        end
      end
      present(order.reload)
    rescue ActiveRecord::RecordInvalid => e
      raise Error, e.record.errors.full_messages.to_sentence
    rescue ArgumentError, KeyError, Orders::Editor::Error, Sendit::Client::Error => e
      raise Error, e.message
    end

    def transition!(order, attrs)
      order.transition_to!(attrs.fetch("status"), reason: attrs["reason"], source: :staff)
    rescue StandardError => e
      raise Error, e.message
    end

    def shipment!(store, order, operation)
      raise Error, "Sendit is not configured." unless store.sendit_configured?
      raise Error, "Shipment operation must be push or refresh. Use cancel_order for cancellations." unless %w[push refresh].include?(operation)
      if operation == "push" && !%w[confirmed preparing awaiting_pickup address_issue].include?(order.status)
        raise Error, "Confirm the order before creating a shipment."
      end

      sync = Sendit::Sync.new(order)
      operation == "push" ? sync.push! : sync.refresh!
      raise Error, order.reload.sendit_error if order.reload.sendit_error.present?
    end

    def label(store, number:)
      order = find(store, number)
      raise Error, "Sendit is not configured." unless store.sendit_configured?

      url = Sendit::Sync.new(order).label_url
      raise Error, "No Sendit label yet." if url.blank?

      { "number" => order.number, "labelUrl" => url }
    rescue Sendit::Client::Error => e
      raise Error, e.message
    end

    def editor_attrs(store, attrs, order: nil)
      reject_unknown!(attrs, EDIT_FIELDS)
      %w[shippingDh discountDh].each do |key|
        next unless attrs.key?(key)

        raise Error, "#{key} must be a non-negative whole currency amount." unless attrs[key].is_a?(Integer) && attrs[key] >= 0
      end
      %w[name phone phoneCountry city district address notes discountCode].each do |key|
        next unless attrs.key?(key)

        raise Error, "#{key} must be a string or null." unless attrs[key].nil? || attrs[key].is_a?(String)
      end
      if attrs.key?("tags") && !(attrs["tags"].is_a?(Array) && attrs["tags"].all? { |tag| tag.is_a?(String) })
        raise Error, "tags must be an array of strings."
      end
      result = if order
        { name: order.customer_name, phone: order.customer_phone, city: order.customer_city,
          district: order.customer_district, address: order.customer_address, notes: order.notes,
          tags: order.tags, shipping_dh: order.shipping_cents / 100.0,
          discount_code: order.discount_code, discount_dh: order.discount_cents / 100.0,
          lines: order.order_items.map { |item| { product_id: item.product_id, product_variant_id: item.product_variant_id, quantity: item.quantity } } }
      else
        { shipping_dh: store.shipping_cents.to_i / 100.0 }
      end
      attrs.except("lines").each { |key, value| result[key.underscore.to_sym] = value }
      result[:lines] = lines(store, attrs["lines"]) if attrs.key?("lines")
      result
    end

    def lines(store, values)
      raise Error, "Provide 1-100 order lines." unless values.is_a?(Array) && values.size.between?(1, 100)

      values.map do |line|
        raise Error, "Each line must be an object." unless line.is_a?(Hash)

        reject_unknown!(line, %w[productSlug variantId quantity])
        quantity = line["quantity"]
        raise Error, "Line quantity must be an integer from 1 to 999." unless quantity.is_a?(Integer) && quantity.between?(1, 999)

        raise Error, "productSlug must be a non-empty string." unless line["productSlug"].is_a?(String) && line["productSlug"].present?
        if line["variantId"].present? && !line["variantId"].to_s.match?(/\A[1-9]\d*\z/)
          raise Error, "variantId must be a positive identifier."
        end

        product = store.products.find_by(slug: line["productSlug"])
        raise Error, "Unknown product in this store." unless product

        variant = if line["variantId"].present?
          product.product_variants.active.find_by(id: line["variantId"])
        end
        raise Error, "Unknown or inactive variant for this product." if line["variantId"].present? && variant.nil?
        raise Error, "Choose an active variant for this product." if product.product_variants.exists? && variant.nil?

        { product_id: product.id, product_variant_id: variant&.id, quantity: quantity }
      end
    end

    def reject_unknown!(attrs, allowed)
      unknown = attrs.keys - allowed
      raise Error, "Unknown fields: #{unknown.join(', ')}" if unknown.any?
    end

    def present(order)
      {
        "number" => order.number, "status" => order.status, "currency" => order.currency,
        "archived" => order.archived?, "tags" => order.tag_list, "notes" => order.notes,
        "editable" => order.editable?, "editLockReason" => order.edit_lock_reason,
        "allowedTransitions" => order.staff_transitions,
        "subtotalDh" => order.subtotal_cents / 100.0, "shippingDh" => order.shipping_cents / 100.0,
        "discountDh" => order.discount_cents / 100.0, "discountCode" => order.discount_code,
        "totalDh" => order.total_cents / 100.0,
        "shipment" => { "code" => order.sendit_code, "status" => order.sendit_status, "error" => order.sendit_error },
        "items" => order.order_items.includes(:product).map { |item|
          { "productSlug" => item.product&.slug, "productName" => item.product_name,
            "variantId" => item.product_variant_id&.to_s, "variantName" => item.variant_name,
            "quantity" => item.quantity, "unitPriceDh" => item.unit_price_cents / 100.0,
            "totalDh" => item.total_cents / 100.0 }
        }
      }
    end
  end
end
