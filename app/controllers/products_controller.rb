class ProductsController < ApplicationController
  SIZE_ORDER = %w[XS S M L XL XXL].freeze
  COLOR_ORDER = [ "Rose poudré", "Blush", "Taupe", "Sand", "Noir", "Black", "Ink" ].freeze

  def show
    @product = current_store.products.active.includes(:collections, :product_variants, :translations).find_by!(slug: params[:slug])
    prepare_variants!

    if landing_page?
      prepare_landing_media!
      render :landing
    else
      @eyebrow = "MOREA ACTIVE"
      @collection = @product.collections.published.order(:position).first
      @gallery = product_gallery
      @related = related_products
    end
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
    uploaded = @product.images.map { |image| helpers.rails_blob_path(image, only_path: true) }
    (uploaded + [ @product.image_url, @product.detail_image_url ]).compact_blank.uniq.presence || [ nil ]
  end

  def related_products
    scope = @collection ? @collection.products : current_store.products
    scope.active.where.not(id: @product.id).includes(:translations, images_attachments: :blob).limit(4)
  end

  def landing_page?
    product_image_path("front.jpg").exist?
  end

  def prepare_landing_media!
    front = public_image_url("front.jpg") || @product.image_url
    side = public_image_url("side.jpg")
    back = public_image_url("back.jpg")
    details = public_image_url("details.jpg") || @product.detail_image_url
    lifestyle = public_image_url("lifestyle.jpg")
    story = public_image_url("story.jpg")

    @hero_image = lifestyle.presence || front
    @story_image = story.presence || front.presence || @product.image_url

    @gallery = [
      { label: t("landing.gallery.front"), url: front },
      { label: t("landing.gallery.side"), url: side },
      { label: t("landing.gallery.back"), url: back },
      { label: t("landing.gallery.details"), url: details }
    ].select { |shot| shot[:url].present? }
  end

  def product_image_path(filename)
    Rails.root.join("public/images/products/#{@product.slug}/#{filename}")
  end

  def public_image_url(filename)
    path = product_image_path(filename)
    "/images/products/#{@product.slug}/#{filename}" if path.exist?
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
