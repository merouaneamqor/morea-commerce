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

    def update
      variant = @product.product_variants.find(params[:id])
      if variant.update(variant_params)
        redirect_to edit_admin_product_path(@product), notice: "Variant updated."
      else
        redirect_to edit_admin_product_path(@product), alert: variant.errors.full_messages.to_sentence
      end
    end

    def destroy
      @product.product_variants.find(params[:id]).destroy!
      redirect_to edit_admin_product_path(@product), notice: "Variant removed."
    end

    private

    def set_product
      @product = current_store.products.find_by!(slug: params[:product_id])
    end

    def variant_params
      params.require(:product_variant).permit(
        :name, :sku, :option1_name, :option1_value, :option2_name, :option2_value,
        :price_cents, :stock, :active
      )
    end
  end
end
