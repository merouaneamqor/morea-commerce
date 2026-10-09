module Admin
  class StoresController < BaseController
    def edit
      @store = current_store
      @store.build_missing_translations!
    end

    def update
      @store = current_store
      if @store.update(store_params)
        redirect_to edit_admin_store_path, notice: "Store settings saved."
      else
        @store.build_missing_translations!
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def store_params
      attrs = params.require(:store).permit(
        :name, :slug, :phone, :whatsapp, :email, :currency,
        :featured_product_id, :featured_collection_id,
        :campaign_image_url, :sendit_pickup_district_id,
        :shipping_dh, :free_shipping_threshold_dh,
        :sendit_allow_open, :sendit_allow_try, :low_stock_threshold,
        :sendit_public_key, :sendit_secret_key, :sendit_webhook_secret,
        :discord_orders_webhook_url,
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
