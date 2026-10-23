module Admin
  class VariantsController < BaseController
    before_action :set_product

    def create
      variant = @product.product_variants.new(variant_params)
      if variant.save
        redirect_to edit_admin_product_path(@product), notice: "Variant added."
      else
        redirect_to edit_admin_product_path(@product), alert: variant.errors.full_messages.to_sentence
      end
    end

    def edit
      @variant = @product.product_variants.find(params[:id])
    end

    def update
      variant = @product.product_variants.find(params[:id])
      ProductVariant.transaction do
        variant.update!(variant_params)
        if params[:product_variant].key?(:media_blob_ids)
          Admin::Variants::MediaUpdater.replace!(variant, params[:product_variant][:media_blob_ids])
        end
        update_images(variant)
      end
      redirect_to edit_admin_product_path(@product), notice: "Variant updated."
    rescue ActiveRecord::RecordInvalid, Admin::Variants::MediaUpdater::Error => error
      redirect_to edit_admin_product_path(@product), alert: error.message
    end

    def destroy
      @product.product_variants.find(params[:id]).destroy!
      redirect_to edit_admin_product_path(@product), notice: "Variant removed."
    end

    def bulk_update
      result = Admin::Variants::BulkUpdater.new(
        product: @product,
        rows: variant_rows,
        destroy_ids: params[:destroy_ids]
      ).call

      if result.success?
        redirect_to edit_admin_product_path(@product), notice: result.message
      else
        redirect_to edit_admin_product_path(@product), alert: result.message
      end
    end

    private

    def set_product
      @product = current_store.products.find_by!(slug: params[:product_id])
    end

    def variant_params
      attrs = params.require(:product_variant).permit(
        :name, :sku, :option1_name, :option1_value, :option2_name, :option2_value,
        :color_hex, :price_cents, :price_dh, :stock, :active
      )
      if attrs.key?(:price_dh)
        dh = attrs.delete(:price_dh)
        attrs[:price_cents] = dh.present? ? dh.to_i * 100 : nil
      end
      attrs
    end

    def update_images(variant)
      remove_ids = Array(params[:product_variant][:remove_image_ids]).compact_blank.map(&:to_i)
      variant.images.where(id: remove_ids).find_each(&:purge_later) if remove_ids.any?

      images = Array(params[:product_variant][:images]).compact_blank
      variant.images.attach(images) if images.any?
    end

    def variant_rows
      raw = params[:variants]
      list = case raw
      when ActionController::Parameters, Hash then raw.values
      when Array then raw
      else []
      end

      list.map do |row|
        h = row.respond_to?(:to_unsafe_h) ? row.to_unsafe_h : row.to_h
        h.with_indifferent_access
      end
    end
  end
end
