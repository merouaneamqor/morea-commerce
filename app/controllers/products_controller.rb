class ProductsController < ApplicationController
  def show
    @product = current_store.products.active.includes(:collections, :product_variants, :translations).find_by!(slug: params[:slug])
    @variants = @product.product_variants.active.order(:name)
    @sizes = @variants.map { |v| v.option1_value.presence || size_from_name(v) }.compact.uniq
    @colors = @variants.map { |v| v.option2_value.presence || color_from_name(v) }.compact.uniq
    @variant_payload = @variants.map do |v|
      {
        id: v.id,
        size: v.option1_value.presence || size_from_name(v),
        color: v.option2_value.presence || color_from_name(v),
        stock: v.stock
      }
    end
    @eyebrow = "MOREA ACTIVE"
  end

  private

  def size_from_name(variant)
    variant.name.to_s.split(" / ").first.presence
  end

  def color_from_name(variant)
    parts = variant.name.to_s.split(" / ")
    parts.length > 1 ? parts.last : nil
  end
end
