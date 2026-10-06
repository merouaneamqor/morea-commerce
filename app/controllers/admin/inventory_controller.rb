module Admin
  class InventoryController < BaseController
    before_action :set_product

    def create
      quantity = params[:quantity].to_i
      reason = params[:reason].to_s.strip.presence || "manual_adjustment"
      note = params[:note].to_s.strip.presence
      variant = @product.product_variants.find_by(id: params[:product_variant_id]) if params[:product_variant_id].present?

      if quantity.zero?
        redirect_to edit_admin_product_path(@product), alert: "Enter a non-zero quantity."
        return
      end

      target = variant || @product
      new_stock = target.stock + quantity
      if new_stock.negative?
        redirect_to edit_admin_product_path(@product), alert: "Stock cannot go below zero."
        return
      end

      ActiveRecord::Base.transaction do
        target.update!(stock: new_stock)
        @product.inventory_movements.create!(
          product_variant: variant,
          quantity: quantity,
          reason: reason,
          note: note
        )
      end

      redirect_to edit_admin_product_path(@product), notice: "Stock adjusted."
    end

    private

    def set_product
      @product = current_store.products.find_by!(slug: params[:product_id])
    end
  end
end
