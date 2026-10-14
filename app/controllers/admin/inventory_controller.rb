module Admin
  class InventoryController < BaseController
    before_action :set_product

    def create
      quantity = params[:quantity].to_i
      reason = params[:reason].to_s.strip.presence || "manual_adjustment"
      note = params[:note].to_s.strip.presence
      variant = @product.product_variants.find_by(id: params[:product_variant_id]) if params[:product_variant_id].present?

      Inventory::Adjuster.adjust!(
        product: @product,
        quantity: quantity,
        reason: reason,
        note: note,
        variant: variant
      )

      redirect_to edit_admin_product_path(@product), notice: "Stock adjusted."
    rescue Inventory::Adjuster::Error => e
      redirect_to edit_admin_product_path(@product), alert: e.message
    end

    private

    def set_product
      @product = current_store.products.find_by!(slug: params[:product_id])
    end
  end
end
