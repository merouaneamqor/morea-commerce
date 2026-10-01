class CartsController < ApplicationController
  before_action :require_store!

  def show
    @cart = current_cart
    @items = @cart.cart_items.includes(:product, :product_variant)
  end

  def add_item
    product = current_store.products.active.find(params[:product_id])
    variant = product.product_variants.active.find_by(id: params[:product_variant_id])
    quantity = params[:quantity].presence || 1
    current_cart.add_product!(product, quantity: quantity, variant: variant)

    redirect_to decide_redirect(product), notice: "Added to bag."
  end

  def update_item
    item = current_cart.cart_items.find(params[:item_id])
    item.update!(quantity: params[:quantity].to_i.clamp(1, 99))
    redirect_to cart_path, notice: "Bag updated."
  end

  def remove_item
    current_cart.cart_items.find(params[:item_id]).destroy!
    redirect_to cart_path, notice: "Item removed."
  end

  private

  def decide_redirect(product)
    params[:checkout].present? ? checkout_path : cart_path
  end
end
