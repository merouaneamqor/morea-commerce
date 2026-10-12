class ProductsController < ApplicationController
  def show
    @product = current_store.products.active.includes(:collections, :product_variants, :translations).find_by!(slug: params[:slug])
    prepare_variants!

    @eyebrow = "MOREA ACTIVE"
    @collection = @product.collections.published.order(:position).first
    @gallery = product_gallery
    @related = related_products
  end

  private

  def prepare_variants!
    @variants = @product.product_variants.active.order(:name)
    @sizes = ordered_sizes(@variants.map { |v| v.size_value || size_from_name(v) }.compact.uniq)
    @colors = @variants.map { |v| v.color_value || color_from_name(v) }.compact.uniq
    @color_hexes = @variants.each_with_object({}) do |v, map|
      color = v.color_value || color_from_name(v)
      next if color.blank?

      map[color] ||= v.color_hex.presence
    end
    @variant_payload = @variants.map do |v|
      {
        id: v.id,
        size: v.size_value || size_from_name(v),
        color: v.color_value || color_from_name(v),
        stock: v.stock
      }
    end.sort_by do |v|
      [ ProductVariant.size_rank(v[:size]), v[:color].to_s.downcase ]
    end
  end

  def product_gallery
    @product.ordered_images.map { |image| helpers.media_url(image) }.presence || [ nil ]
  end

  def related_products
    scope = @collection ? @collection.products : current_store.products
    scope.active.where.not(id: @product.id).includes(:translations, images_attachments: :blob).limit(4)
  end

  def ordered_sizes(sizes)
    sizes.sort_by { |s| ProductVariant.size_rank(s) }
  end

  # Legacy fallback when option columns were empty and name held "Size / Color".
  def size_from_name(variant)
    variant.name.to_s.split(" / ").first.presence
  end

  def color_from_name(variant)
    parts = variant.name.to_s.split(" / ")
    parts.length > 1 ? parts.last : nil
  end
end
