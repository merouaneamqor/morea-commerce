# frozen_string_literal: true

module Admin
  class OrdersController < BaseController
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
      "returns" => ->(scope) { scope.where(status: "returned") }
    }.freeze

    def index
      @status = params[:status]
      @archived = @status == "archived"
      @connections = current_store.store_connections.order(:name)
      @shopify_connections = @connections.where(provider: "shopify", shopify_oauth: true).limit(100)
      @orders = visible_orders.recent.includes(:customer, external_order_receipt: :store_connection)
      if params[:connection_id].present?
        connection = current_store.store_connections.find(params[:connection_id])
        @orders = @orders.joins(:external_order_receipt).where(external_order_receipts: { store_connection_id: connection.id })
      end
      @orders = if @archived
        @orders.archived
      else
        @orders.active
      end
      @agents = current_store.users.active.where(confirmation_role: "agent").or(current_store.users.active.where(admin: true)).order(:email)
      if params[:agent_id].present? && !agent_view?
        @orders = params[:agent_id] == "none" ? @orders.left_joins(:order_confirmation).where(order_confirmations: { assigned_user_id: nil }) :
          @orders.joins(:order_confirmation).where(order_confirmations: { assigned_user_id: @agents.find(params[:agent_id]).id })
      end
      @group_counts = ORDER_GROUPS.keys.index_with { |key| group_scope(@orders, key).count } unless @archived
      @group = ORDER_GROUPS.key?(params[:group]) ? params[:group] : nil
      @orders = group_scope(@orders, @group) if @group && !@archived
      @orders = @orders.includes(order_confirmation: :assigned_user)
      @orders = @orders.by_status(@status) if @status.present? && !@archived
      @orders = @orders.where(status: Order::PROBLEM_STATUSES) if params[:attention] == "delivery_issues"
      if params[:q].present?
        q = "%#{Order.sanitize_sql_like(params[:q].strip)}%"
        @orders = @orders.where(
          "number ILIKE :q OR customer_name ILIKE :q OR customer_phone ILIKE :q OR COALESCE(tags, '') ILIKE :q",
          q: q
        )
      end
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
    end

    def create
      editor = Orders::Editor.new(store: current_store, user: current_user)
      @order = editor.create(editor_attrs)
      if @order
        redirect_to admin_order_path(@order), notice: "Order created."
      else
        @order = current_store.orders.new(fallback_order_attrs)
        @line_items = preview_lines
        @editor_errors = editor.errors
        @assignable_agents = assignable_agents
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
  cents = params[:amount].present? ? parse_mad_cents(params[:amount]) : @order.total_cents
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

    def group_scope(scope, key)
      ORDER_GROUPS.fetch(key).call(scope)
    end

    def require_shopify_workspace!
      head :not_found unless current_store
    end

    def set_order
      @order = visible_orders.find(params[:id])
    end

    def agent_view?
      current_user.confirmation_agent_view?
    end

    # Agents may look at orders (never change them here): unassigned ones and their own,
    # not the ones another agent holds. Owners and managers see everything of the store.
    def visible_orders
      return current_store.orders unless agent_view?

      held_by_others = OrderConfirmation.where(store: current_store).where.not(assigned_user_id: [ nil, current_user.id ]).select(:order_id)
      current_store.orders.where.not(id: held_by_others)
    end

    def agents_read_only!
      return unless agent_view?
      return if %w[index show].include?(action_name)

      redirect_to admin_orders_path, alert: "Agents can look at orders but not change them here."
    end

    def assignable_agents
      current_store.users.active.where(confirmation_role: "agent").order(:name, :email)
    end

    def order_params
      params.require(:order).permit(:notes)
    end

    def editor_attrs
      raw = params.fetch(:order, {}).permit(
        :name, :phone, :phone_country, :city, :district, :address, :notes, :tags,
        :shipping_dh, :discount_code, :discount_dh, :agent_id,
        lines: [ :product_id, :product_variant_id, :quantity ]
      )
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
