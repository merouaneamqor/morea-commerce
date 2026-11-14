# frozen_string_literal: true

module Admin
  class OrdersController < BaseController
    include DateRangeSelection

    # The new-order window is a Turbo frame: the frame answer carries no page layout.
    layout :orders_layout

    before_action :require_shopify_workspace!, only: :shopify_sync_all
    before_action :agents_read_only!
    helper_method :agent_view?
    before_action :set_order, only: %i[
      show edit update transition sendit sendit_label ozon ozon_label ameex
      duplicate archive unarchive packing_slip comments tags collect refund complete_import_contact
    ]

    IN_PROGRESS = (Order::FLOW - %w[new confirmed preparing delivered] + Order::PROBLEM_STATUSES).freeze

    # Tabs on the orders list: confirmation outcome while an order is new, delivery stage after.
    ORDER_GROUPS = {
      "all" => ->(scope) { scope },
      "new" => ->(scope) { scope.left_joins(:order_confirmation).where(status: "new").where(order_confirmations: { disposition: [ nil, "pending" ] }) },
      "no_answer" => ->(scope) { scope.joins(:order_confirmation).where(status: "new", order_confirmations: { disposition: "no_answer" }) },
      "callbacks" => ->(scope) { scope.joins(:order_confirmation).where(status: "new", order_confirmations: { disposition: "callback" }) },
      "confirmed" => ->(scope) { scope.where(status: %w[confirmed preparing]) },
      "cancelled" => ->(scope) { scope.where(status: "cancelled") },
      "in_progress" => ->(scope) { scope.where(status: IN_PROGRESS) },
      "delivered" => ->(scope) { scope.where(status: "delivered") },
      "returns" => ->(scope) { scope.where(status: "returned") },
      "wrong_number" => ->(scope) { scope.joins(:order_confirmation).where(status: "new", order_confirmations: { disposition: "wrong_number" }) },
      "blocked" => ->(scope) { scope.joins(:order_confirmation).where(status: "new", order_confirmations: { disposition: "blocked" }) }
    }.freeze

    SHIP_JOBS = { "sendit" => SenditSyncJob, "ozon" => OzonSyncJob, "ameex" => AmeexSyncJob }.freeze
    PER_PAGE = 25
    # Older links (the dashboard cards, bookmarks) carry these: they keep working, and open on every date.
    LEGACY_FILTERS = %i[status group attention].freeze
    CONFIRMATION_FILTERS = %w[pending planned confirmed cancelled wrong].freeze
    SHIPPING_FILTERS = Orders::Overview::SHIPPING_GROUPS.keys.freeze

    # The orders page: the figures of Orders::Overview (confirmation, shipping) for the date range, then the table, which
    # applies the same date range and the filters. Without a filter, the number of rows is the "Commandes totales" card.
    def index
      @status = params[:status]
      @archived = @status == "archived"
      @connections = current_store.store_connections.order(:name)
      @shopify_connections = @connections.where(provider: "shopify", shopify_oauth: true).limit(100)
      @agents = current_store.users.active.where(confirmation_role: "agent").or(current_store.users.active.where(admin: true)).order(:email)
      @products = current_store.products.visible.order(:name).pluck(:name, :id)
      @companies = connected_companies
      @date_range = selected_date_range(scope: "orders", default: "last_30")
      @overview = Orders::Overview.new(scope: visible_orders.active, range: @date_range)

      orders = visible_orders.recent.preload(:customer, :order_items, order_confirmation: :assigned_user, external_order_receipt: :store_connection)
      orders = @archived ? orders.archived : orders.active
      @date_filtered = params[:from].present? || LEGACY_FILTERS.none? { |key| params[key].present? }
      orders = orders.where(created_at: @date_range.time_range) if @date_filtered && !@archived
      orders = filter_orders(orders)

      @total_count = orders.count
      @page = [ params[:page].to_i, 1 ].max
      @orders = orders.offset((@page - 1) * PER_PAGE).limit(PER_PAGE + 1).to_a
      @has_next = @orders.length > PER_PAGE
      @orders = @orders.first(PER_PAGE)
    end

    def show
      @events = @order.order_events.includes(:user).recent
      render :agent_show if agent_view?
    end

    def new
      @order = current_store.orders.new(
        currency: current_store.currency,
        shipping_cents: current_store.shipping_cents.to_i
      )
      @line_items = []
      @assignable_agents = assignable_agents
      @companies = connected_companies
    end

    def create
      editor = Orders::Editor.new(store: current_store, user: current_user)
      @order = editor.create(editor_attrs)
      if @order
        attribute_to_creator(@order) if agent_view?
        redirect_to admin_order_path(@order), notice: "Order created."
      else
        @order = current_store.orders.new(fallback_order_attrs)
        @line_items = preview_lines
        @editor_errors = editor.errors
        @assignable_agents = assignable_agents
        @companies = connected_companies
        flash.now[:alert] = editor.errors.full_messages.to_sentence.presence || "Could not create order."
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      unless @order.editable?
        redirect_to admin_order_path(@order), alert: @order.edit_lock_reason
        return
      end
      @line_items = @order.order_items.map { |item| line_preview(item) }
    end

    def update
      # Notes / tags-only updates from the show page still use this action
      if params[:order].present? && !params[:order].key?(:lines) && order_params.keys.map(&:to_s) == %w[notes]
        if @order.update(order_params)
          redirect_to admin_order_path(@order), notice: "Order updated."
        else
          @events = @order.order_events.includes(:user).recent
          render :show, status: :unprocessable_entity
        end
        return
      end

      unless @order.editable?
        redirect_to admin_order_path(@order), alert: @order.edit_lock_reason
        return
      end

      editor = Orders::Editor.new(store: current_store, user: current_user)
      if editor.update(@order, editor_attrs)
        redirect_to admin_order_path(@order), notice: "Order updated."
      else
        @line_items = preview_lines
        @editor_errors = editor.errors
        flash.now[:alert] = editor.errors.full_messages.to_sentence.presence || "Could not update order."
        render :edit, status: :unprocessable_entity
      end
    end

    def transition
      @order.transition_to!(params[:to_status], reason: params[:cancel_reason], user: current_user, source: :staff)
      label = Order::STATUS_LABELS.fetch(params[:to_status].to_s, params[:to_status].to_s.humanize)
      redirect_to admin_order_path(@order), notice: "Order marked as #{label.downcase}."
    rescue ArgumentError, StandardError => e
      redirect_to admin_order_path(@order), alert: e.message
    end

    def complete_import_contact
      attrs = params.require(:contact).permit(:name, :phone, :city, :address, :district).to_h.symbolize_keys
      Orders::CompleteImportedContact.new(store: current_store, user: current_user).call(order: @order, attrs: attrs)
      redirect_to admin_order_path(@order), notice: t("import_contact.saved")
    rescue Orders::CompleteImportedContact::Error => error
      redirect_to admin_order_path(@order), alert: error.message
    end

    def duplicate
      editor = Orders::Editor.new(store: current_store, user: current_user)
      copy = editor.duplicate(@order)
      if copy
        redirect_to admin_order_path(copy), notice: "Duplicated as ##{copy.number}."
      else
        redirect_to admin_order_path(@order), alert: editor.errors.full_messages.to_sentence.presence || "Could not duplicate."
      end
    end

    def archive
      @order.archive!(user: current_user)
      redirect_to admin_order_path(@order), notice: "Order archived."
    end

    def unarchive
      @order.unarchive!(user: current_user)
      redirect_to admin_order_path(@order), notice: "Order unarchived."
    end

    def packing_slip
      render layout: "admin_print"
    end

    def comments
      editor = Orders::Editor.new(store: current_store, user: current_user)
      if editor.add_comment(@order, params[:body])
        redirect_to admin_order_path(@order), notice: "Comment added."
      else
        redirect_to admin_order_path(@order), alert: editor.errors.full_messages.to_sentence
      end
    end

def collect
  cents = params[:amount].present? ? parse_mad_cents(params[:amount]) : @order.to_collect_cents
  @order.record_collection!(cents: cents, user: current_user)
  redirect_to admin_order_path(@order), notice: "COD payment recorded."
rescue ArgumentError, ActiveRecord::RecordInvalid => e
  redirect_to admin_order_path(@order), alert: e.message
end

def refund
  @order.record_refund!(cents: parse_mad_cents(params[:amount]), user: current_user)
  redirect_to admin_order_path(@order), notice: "Refund recorded."
rescue ArgumentError, ActiveRecord::RecordInvalid => e
  redirect_to admin_order_path(@order), alert: e.message
end

    def tags
      editor = Orders::Editor.new(store: current_store, user: current_user)
      editor.update_tags(@order, params[:tags])
      redirect_to admin_order_path(@order), notice: "Tags saved."
    end

    def product_search
      products = Orders::ProductSearch.new(store: current_store, query: params[:q]).products
      render json: products.flat_map { |product| search_items(product) }.first(25)
    end

    # "+ Créer le produit" on the order form: a minimal product made on the spot, then picked as a line.
    def quick_product
      name = params[:name].to_s.strip
      price = begin
        parse_mad_cents(params[:price])
      rescue ArgumentError
        nil
      end
      if name.blank? || price.nil? || price <= 0
        return render(json: { error: "Enter a product name and a price above 0." }, status: :unprocessable_entity)
      end

      product = current_store.products.create!(name: name, price_cents: price, status: "active", slug: unique_slug(name))
      render json: search_items(product).first, status: :created
    rescue ActiveRecord::RecordInvalid => e
      render json: { error: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
    end

    # Send / retry / refresh / cancel the Sendit parcel for one order
    def sendit
      return redirect_to(admin_order_path(@order), alert: "Sendit is not configured.") unless current_store.sendit_configured?

      if params[:district_id].present?
        district = Sendit::Districts.find(params[:district_id], store: current_store)
        @order.update!(sendit_district_id: district&.dig(:id), sendit_district_name: district&.dig(:name))
      end

      sync = Sendit::Sync.new(@order)
      case params[:op]
      when "cancel" then sync.cancel!
      when "refresh" then sync.refresh!
      else sync.push!
      end

      if @order.reload.sendit_error.present?
        redirect_to admin_order_path(@order), alert: "Sendit: #{@order.sendit_error}"
      else
        redirect_to admin_order_path(@order), notice: "Sendit: parcel #{@order.sendit_code} — #{@order.sendit_label}."
      end
    end

    def sendit_label
      url = Sendit::Sync.new(@order).label_url
      url.present? ? redirect_to(url, allow_other_host: true) : redirect_to(admin_order_path(@order), alert: "No Sendit label yet.")
    rescue Sendit::Client::Error => e
      redirect_to admin_order_path(@order), alert: "Sendit: #{e.message}"
    end

    def sendit_sync_all
      return redirect_to(admin_orders_path, alert: "Sendit is not configured.") unless current_store.sendit_configured?

      count = Sendit::Sync.enqueue_all(current_store.orders)
      redirect_to admin_orders_path, notice: "Syncing #{count} orders with Sendit in the background."
    end


    def ozon
      return redirect_to(admin_order_path(@order), alert: "Ozon Express is not configured.") unless current_store.ozon_configured?

      if params[:city_id].present?
        city = Ozon::Cities.find(params[:city_id], store: current_store)
        @order.update!(ozon_city_id: city&.dig(:id), ozon_city_name: city&.dig(:name))
      end

      sync = Ozon::Sync.new(@order)
      case params[:op]
      when "cancel" then sync.cancel!
      when "refresh" then sync.refresh!
      else sync.push!
      end

      if @order.reload.ozon_error.present?
        redirect_to admin_order_path(@order), alert: "Ozon: #{@order.ozon_error}"
      else
        redirect_to admin_order_path(@order), notice: "Ozon: parcel #{@order.ozon_code} — #{@order.ozon_label}."
      end
    end

    def ozon_label
      url = Ozon::Sync.new(@order).label_url
      url.present? ? redirect_to(url, allow_other_host: true) : redirect_to(admin_order_path(@order), alert: "No Ozon label yet.")
    rescue Ozon::Client::Error => e
      redirect_to admin_order_path(@order), alert: "Ozon: #{e.message}"
    end

    def ozon_sync_all
      return redirect_to(admin_orders_path, alert: "Ozon Express is not configured.") unless current_store.ozon_configured?

      count = Ozon::Sync.enqueue_all(current_store.orders)
      redirect_to admin_orders_path, notice: "Syncing #{count} orders with Ozon Express in the background."
    end

    def ameex
      return redirect_to(admin_order_path(@order), alert: "Ameex is not configured.") unless current_store.ameex_configured?

      if params[:city_id].present?
        city = Ameex::Cities.find(params[:city_id], store: current_store)
        @order.update!(ameex_city_id: city&.dig(:id), ameex_city_name: city&.dig(:name))
      end

      sync = Ameex::Sync.new(@order)
      case params[:op]
      when "cancel" then sync.cancel!
      when "refresh" then sync.refresh!
      else sync.push!
      end

      if @order.reload.ameex_error.present?
        redirect_to admin_order_path(@order), alert: "Ameex: #{@order.ameex_error}"
      else
        redirect_to admin_order_path(@order), notice: "Ameex: parcel #{@order.ameex_code} — #{@order.ameex_label}."
      end
    end

    def ameex_sync_all
      return redirect_to(admin_orders_path, alert: "Ameex is not configured.") unless current_store.ameex_configured?

      count = Ameex::Sync.enqueue_all(current_store.orders)
      redirect_to admin_orders_path, notice: "Syncing #{count} orders with Ameex in the background."
    end

    # Confirmed orders waiting for a parcel, checked for duplicates, blocked numbers and customers who cancelled before.
    def ship_review
      return redirect_to(admin_orders_path, alert: t("orders_ship.unavailable")) unless ship_available?

      @review = Orders::ShipmentReview.new(store: current_store)
    end

    # Sends the ticked parcels. The server checks again: held-back rows (duplicates, blocked, incomplete) never go, whatever the form says.
    def ship_confirmed
      return redirect_to(admin_orders_path, alert: t("orders_ship.unavailable")) unless ship_available?

      ids = Array(params[:order_ids]).map(&:to_i).uniq
      return redirect_to(ship_review_admin_orders_path, alert: t("orders_ship.none")) if ids.empty?

      rows = Orders::ShipmentReview.new(store: current_store).rows.select { |row| ids.include?(row.order.id) }
      sendable = rows.select(&:selectable?)
      held = ids.size - sendable.size
      return redirect_to(admin_orders_path, notice: t("orders_ship.demo", count: sendable.size), status: :see_other) if Demo::Workspace.demo_store?(current_store)

      sent = sendable.count do |row|
        # One click only: the same order is not queued twice if the button is pressed twice.
        next false unless Rails.cache.write("ship_confirmed:#{row.order.id}", 1, expires_in: 5.minutes, unless_exist: true)

        SHIP_JOBS.fetch(row.carrier).perform_later(row.order.id, "push")
      end
      message = t("orders_ship.sent", count: sent)
      message += t("orders_ship.skipped", count: held) if held.positive?
      redirect_to admin_orders_path, notice: message, status: :see_other
    end

    def shopify_sync_all
      unless Connections::ShopifyOauth.configured?
        return redirect_to admin_orders_path, alert: t("connections.shopify_api.errors.config_missing"), status: :see_other
      end

      count = Connections::ShopifySyncRequest.call(store: current_store)
      redirect_to admin_orders_path, notice: t("shopify_sync.queued", count: count), status: :see_other
    rescue Connections::ShopifySyncRequest::Error
      redirect_to admin_orders_path, alert: t("shopify_sync.connect_first"), status: :see_other
    end

    private

    # Every filter of the page. They only narrow the table; the cards above never depend on them. Each one reads ids
    # through subqueries scoped to this workspace, so a crafted id cannot reach another store's records.
    def filter_orders(orders)
      orders = orders.by_status(@status) if @status.present? && !@archived
      orders = orders.where(status: Order::PROBLEM_STATUSES) if params[:attention] == "delivery_issues"
      group = ORDER_GROUPS.key?(params[:group]) ? params[:group] : nil
      orders = group_scope(orders, group) if group && !@archived
      orders = confirmation_filter(orders, params[:confirmation])
      orders = orders.where(status: Orders::Overview::SHIPPING_GROUPS.fetch(params[:shipping])) if SHIPPING_FILTERS.include?(params[:shipping])
      orders = orders.where.not(collected_at: nil) if params[:payment] == "paid"
      orders = orders.awaiting_remittance if params[:payment] == "unpaid"
      orders = company_filter(orders)
      orders = agent_filter(orders)
      orders = source_filter(orders)
      if params[:product].present?
        product_ids = current_store.products.where(id: params[:product]).select(:id)
        orders = orders.where(id: OrderItem.where(product_id: product_ids).select(:order_id))
      end
      if params[:missed] == "1"
        orders = orders.where(id: ConfirmationAttempt.joins(:order_confirmation).where(store: current_store, outcome: "no_answer").select("order_confirmations.order_id"))
      end
      if params[:q].present?
        q = "%#{Order.sanitize_sql_like(params[:q].strip)}%"
        orders = orders.where("orders.number ILIKE :q OR orders.customer_name ILIKE :q OR orders.customer_phone ILIKE :q OR COALESCE(orders.tags, '') ILIKE :q", q: q)
      end
      orders
    end

    # Where the order is in the call centre. "pending" counts the scheduled callbacks too, like the "En attente" card.
    def confirmation_filter(orders, key)
      return orders unless CONFIRMATION_FILTERS.include?(key)

      confirmations = OrderConfirmation.where(store: current_store)
      wrong = confirmations.where(disposition: %w[wrong_number blocked]).select(:order_id)
      case key
      when "pending" then orders.where(status: "new").where.not(id: wrong)
      when "planned" then orders.where(status: "new", id: confirmations.where(disposition: "callback").select(:order_id))
      when "confirmed" then orders.where(status: Orders::Overview::CONFIRMED_STATUSES)
      when "cancelled" then orders.where(status: "cancelled")
      when "wrong" then orders.where(status: "new", id: wrong)
      end
    end

    # The delivery companies this store is connected to through their API (an active account that was connected): the only
    # ones the company filter offers, and none for an agent. A company that is not connected never shows up.
    def connected_companies
      return [] if agent_view?

      current_store.delivery_accounts.where(is_active: true).where.not(connected_at: nil).order(:provider).pluck(:provider).uniq
        .map { |provider| [ Carriers.provider(provider)["name"], provider ] }
    end

    # An order belongs to a company when it was created with that company, or (Sendit) when its parcel carries a Sendit code.
    def company_filter(orders)
      key = params[:company]
      return orders if key.blank? || @companies.empty?
      return orders.where(delivery_provider: nil, sendit_code: [ nil, "" ]) if key == "none"
      return orders unless @companies.any? { |_name, provider| provider == key }

      by_choice = orders.where(delivery_provider: key)
      key == "sendit" ? by_choice.or(orders.where.not(sendit_code: [ nil, "" ])) : by_choice
    end

    # The agent holding the order's claim ("none" for unassigned). Not offered to agents.
    def agent_filter(orders)
      return orders if params[:agent_id].blank? || agent_view?

      assigned = OrderConfirmation.where(store: current_store).where.not(assigned_user_id: nil)
      return orders.where.not(id: assigned.select(:order_id)) if params[:agent_id] == "none"

      orders.where(id: assigned.where(assigned_user_id: @agents.find(params[:agent_id]).id).select(:order_id))
    end

    def source_filter(orders)
      return orders if params[:connection_id].blank?
      return orders.where.not(id: ExternalOrderReceipt.select(:order_id)) if params[:connection_id] == "manual"

      connection = current_store.store_connections.find(params[:connection_id])
      orders.where(id: ExternalOrderReceipt.where(store_connection_id: connection.id).select(:order_id))
    end

    def group_scope(scope, key)
      ORDER_GROUPS.fetch(key).call(scope)
    end

    def require_shopify_workspace!
      head :not_found unless current_store
    end

    def set_order
      @order = visible_orders.find(params[:id])
    end

    def orders_layout = turbo_frame_request? ? false : "admin"

    def agent_view?
      current_user.confirmation_agent_view?
    end

    # Agents may look at orders (never change them here): unassigned ones and their own,
    # not the ones another agent holds. Owners and managers see everything of the store.
    def visible_orders
      return current_store.orders unless agent_view?

      Confirmations::AgentOrders.new(store: current_store, user: current_user).scope
    end

    # An order an agent types is theirs: it is attributed to them (not claimed), so it shows in their list and queue even when the owner's
    # attribution rules decide who gets what.
    def attribute_to_creator(order)
      confirmation = OrderConfirmation.find_or_create_by!(order: order) { |row| row.store = current_store }
      confirmation.update!(attributed_user: current_user, attributed_at: Time.current)
      order.record_event!("comment", body: "Created by the agent and attributed to them", user: current_user)
    end

    def ship_available?
      Demo::Workspace.demo_store?(current_store) || Orders::ShipmentReview::CARRIERS.any? { |carrier| current_store.public_send("#{carrier}_configured?") }
    end

    def agents_read_only!
      return unless agent_view?
      return if %w[index show new create product_search].include?(action_name)

      redirect_to admin_orders_path, alert: "Agents can look at orders and create new ones, but not change existing ones here."
    end

    def assignable_agents
      return User.none if agent_view?

      current_store.users.active.where(confirmation_role: "agent").order(:name, :email)
    end

    def order_params
      params.require(:order).permit(:notes)
    end

    def editor_attrs
      raw = params.fetch(:order, {}).permit(
        :name, :phone, :phone_country, :city, :district, :address, :notes, :tags,
        :shipping_dh, :discount_code, :discount_dh, :agent_id, :second_phone, :delivery_provider, :scheduled_for, :advance_dh, :shipping_excluded,
        lines: [ :product_id, :product_variant_id, :quantity ]
      )
      raw = raw.except(:agent_id) if agent_view? # an agent cannot hand the order to someone else
      lines = raw[:lines]
      lines = lines.values if lines.respond_to?(:values) && !lines.is_a?(Array)
      raw.to_h.symbolize_keys.merge(lines: Array(lines))
    end

    def fallback_order_attrs
      {
        customer_name: params.dig(:order, :name),
        customer_phone: params.dig(:order, :phone),
        customer_city: params.dig(:order, :city),
        customer_district: params.dig(:order, :district),
        customer_address: params.dig(:order, :address),
        second_phone: params.dig(:order, :second_phone),
        delivery_provider: params.dig(:order, :delivery_provider).presence,
        scheduled_for: (ActiveSupport::TimeZone[DateRange::ZONE].parse(params.dig(:order, :scheduled_for).to_s) rescue nil),
        advance_cents: [ (params.dig(:order, :advance_dh).to_f * 100).round, 0 ].max,
        notes: params.dig(:order, :notes),
        tags: params.dig(:order, :tags),
        discount_code: params.dig(:order, :discount_code),
        discount_cents: (params.dig(:order, :discount_dh).to_f * 100).round,
        shipping_cents: (params.dig(:order, :shipping_dh).to_f * 100).round,
        currency: current_store.currency
      }
    end

    def preview_lines
      raw_lines = params.dig(:order, :lines)
      raw_lines = raw_lines.values if raw_lines.respond_to?(:values) && !raw_lines.is_a?(Array)
      Array(raw_lines).filter_map do |line|
        next unless line.respond_to?(:to_unsafe_h) || line.is_a?(Hash)

        h = line.respond_to?(:to_unsafe_h) ? line.to_unsafe_h : line.to_h
        h = h.with_indifferent_access
        next if h[:product_id].blank? || h[:quantity].to_i <= 0

        product = current_store.products.find_by(id: h[:product_id])
        next unless product

        variant = h[:product_variant_id].present? ? product.product_variants.find_by(id: h[:product_variant_id]) : nil
        {
          product_id: product.id,
          product_variant_id: variant&.id,
          label: [ product.name, variant&.display_name ].compact.join(" — "),
          quantity: h[:quantity].to_i,
          unit_price_cents: variant&.unit_price_cents || product.price_cents,
          image_url: helpers.product_image_url(product)
        }
      end
    end

    def line_preview(item)
      {
        product_id: item.product_id,
        product_variant_id: item.product_variant_id,
        label: [ item.product_name, item.variant_name ].compact.join(" — "),
        quantity: item.quantity,
        unit_price_cents: item.unit_price_cents,
        image_url: item.product && helpers.product_image_url(item.product)
      }
    end

    def search_items(product)
      image = helpers.product_image_url(product)
      variants = product.product_variants.select(&:active)
      return variants.map { |variant| search_item(product, variant, image) } if variants.any?

      [ search_item(product, nil, image) ]
    end

    def search_item(product, variant, image)
      price = variant&.unit_price_cents || product.price_cents
      {
        product_id: product.id,
        product_variant_id: variant&.id,
        label: variant ? "#{product.name} — #{variant.display_name}" : product.name,
        price_cents: price,
        price_display: money_label(price),
        stock: product.track_inventory ? (variant ? variant.stock : product.stock) : nil,
        image_url: image
      }
    end

    def unique_slug(name)
      base = name.parameterize.presence || "product"
      slug = base
      slug = "#{base}-#{SecureRandom.hex(2)}" while current_store.products.exists?(slug: slug)
      slug
    end

    def money_label(cents)
      "#{(cents.to_i / 100).to_fs(:delimited)} #{current_store.currency}"
    end
  end
end
