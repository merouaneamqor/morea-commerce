class ProductsController < ApplicationController
  SIZE_ORDER = %w[XS S M L XL XXL].freeze
  COLOR_ORDER = [ "Rose poudré", "Blush", "Taupe", "Sand", "Noir", "Black", "Ink" ].freeze

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
    @sizes = ordered_sizes(@variants.map { |v| v.option1_value.presence || size_from_name(v) }.compact.uniq)
    @colors = ordered_colors(@variants.map { |v| v.option2_value.presence || color_from_name(v) }.compact.uniq)
    @variant_payload = @variants.map do |v|
      {
        id: v.id,
        size: v.option1_value.presence || size_from_name(v),
        color: v.option2_value.presence || color_from_name(v),
        stock: v.stock
      }
    end.sort_by do |v|
      [ SIZE_ORDER.index(v[:size].to_s.upcase) || 99, COLOR_ORDER.index(v[:color].to_s) || 99 ]
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
    sizes.sort_by { |s| SIZE_ORDER.index(s.to_s.upcase) || 99 }
  end

  def ordered_colors(colors)
    colors.sort_by { |c| COLOR_ORDER.index(c.to_s) || COLOR_ORDER.map(&:downcase).index(c.to_s.downcase) || 99 }
  end

  def size_from_name(variant)
    variant.name.to_s.split(" / ").first.presence
  end

  def color_from_name(variant)
    parts = variant.name.to_s.split(" / ")
    parts.length > 1 ? parts.last : nil
  end
end
