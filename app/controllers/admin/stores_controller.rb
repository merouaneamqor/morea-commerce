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
      params.require(:store).permit(
        :name, :slug, :phone, :email, :currency,
        :featured_product_id, :featured_collection_id,
        :campaign_image_url,
        translations_attributes: %i[
          id locale tagline about cod_label cod_note
          campaign_title campaign_season campaign_cta
        ]
      )
    end
  end
end
