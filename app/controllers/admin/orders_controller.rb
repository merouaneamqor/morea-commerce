# frozen_string_literal: true

module Admin
  class OrdersController < BaseController
    before_action :set_order, only: %i[
      show edit update transition sendit sendit_label
      duplicate archive unarchive packing_slip comments tags
    ]

    def index
      @status = params[:status]
      @archived = @status == "archived"
      @orders = current_store.orders.recent.includes(:customer)
      @orders = if @archived
        @orders.archived
      else
        @orders.active
      end
      @orders = @orders.by_status(@status) if @status.present? && !@archived
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
    end

    def new
      @order = current_store.orders.new(
        currency: current_store.currency,
        shipping_cents: current_store.shipping_cents.to_i
      )
      @line_items = []
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

    def tags
      editor = Orders::Editor.new(store: current_store, user: current_user)
      editor.update_tags(@order, params[:tags])
      redirect_to admin_order_path(@order), notice: "Tags saved."
    end

    def product_search
      q = params[:q].to_s.strip
      products = current_store.products.active.includes(:product_variants, images_attachments: :blob).limit(20)
      if q.present?
        like = "%#{Order.sanitize_sql_like(q)}%"
        products = products.where("name ILIKE :q OR sku ILIKE :q OR slug ILIKE :q", q: like)
      end

      results = products.flat_map do |product|
        image = helpers.product_image_url(product)
        variants = product.product_variants.active
        if variants.any?
          variants.map do |variant|
            {
              product_id: product.id,
              product_variant_id: variant.id,
              label: "#{product.name} — #{variant.display_name}",
              price_cents: variant.unit_price_cents,
              price_display: money_label(variant.unit_price_cents),
              stock: product.track_inventory ? variant.stock : nil,
              image_url: image
            }
          end
        else
          [ {
            product_id: product.id,
            product_variant_id: nil,
            label: product.name,
            price_cents: product.price_cents,
            price_display: money_label(product.price_cents),
            stock: product.track_inventory ? product.stock : nil,
            image_url: image
          } ]
        end
      end

      render json: results.first(25)
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

    private

    def set_order
      @order = current_store.orders.find(params[:id])
    end

    def order_params
      params.require(:order).permit(:notes)
    end

    def editor_attrs
      raw = params.fetch(:order, {}).permit(
        :name, :phone, :phone_country, :city, :district, :address, :notes, :tags,
        :shipping_dh, :discount_code, :discount_dh,
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

    def money_label(cents)
      "#{(cents.to_i / 100).to_fs(:delimited)} #{current_store.currency}"
    end
  end
end
