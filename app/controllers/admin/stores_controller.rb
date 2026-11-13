module Admin
  class StoresController < BaseController
    before_action :require_workspace!
    def edit
      @store = current_store
      @store.build_missing_translations!
    end

    def update
      @store = current_store
      if update_workspace
        redirect_to edit_admin_store_path, notice: "Store settings saved."
      else
        @store.build_missing_translations!
        render :edit, status: :unprocessable_entity
      end
    end

    # The store's logo has its own small form (choose a file, it is saved; or remove it), apart from the long settings form.
    def logo
      @store = current_store
      if params.dig(:store, :remove_logo) == "1"
        @store.logo.purge_later
        redirect_to edit_admin_store_path(anchor: "logo"), notice: "Logo removed."
      elsif params.dig(:store, :logo).present? && @store.update(logo: params[:store][:logo])
        redirect_to edit_admin_store_path(anchor: "logo"), notice: "Logo saved."
      else
        redirect_to edit_admin_store_path(anchor: "logo"), alert: @store.errors.full_messages.to_sentence.presence || "Choose an image first."
      end
    end

    private

    def require_workspace!
      redirect_to admin_platform_path unless current_store
    end

    def update_workspace
      @store.with_lock do
        was_enabled = @store.storefront_enabled?
        @store.logo.purge_later if params.dig(:store, :remove_logo) == "1" && params.dig(:store, :logo).blank?
        @store.update!(store_params)
        @store.install_online_store_defaults! if !was_enabled && @store.storefront_enabled?
      end
      true
    rescue ActiveRecord::RecordInvalid
      false
    end

    def store_params
      attrs = params.require(:store).permit(
        :name, :logo, :slug, :phone, :whatsapp, :email, :currency, :storefront_enabled, :admin_theme,
        :featured_product_id, :featured_collection_id,
        :campaign_image_url, :sendit_pickup_district_id,
        :shipping_dh, :free_shipping_threshold_dh,
        :sendit_allow_open, :sendit_allow_try, :low_stock_threshold,
        :sendit_public_key, :sendit_secret_key, :sendit_webhook_secret,
        :discord_orders_webhook_url,
        :legal_entity_name, :cndp_authorization, :privacy_rights_contact,
        translations_attributes: %i[
          id locale tagline about cod_label cod_note
          campaign_title campaign_season campaign_cta announcement
        ]
      )

      # Blank password-style fields keep the saved secret
      %i[sendit_public_key sendit_secret_key sendit_webhook_secret discord_orders_webhook_url].each do |key|
        attrs.delete(key) if attrs[key].blank?
      end

      attrs
    end
  end
end
