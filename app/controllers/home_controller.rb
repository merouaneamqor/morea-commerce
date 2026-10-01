class HomeController < ApplicationController
  def index
    @store = current_store
    @store&.translations&.load if @store
    @featured = @store&.featured_product || @store&.products&.active&.featured&.first || @store&.products&.active&.first
    @collection = @store&.featured_collection || @store&.collections&.published&.first
    @collection_products =
      if @collection
        @collection.products.active.includes(:translations).limit(3)
      else
        Product.none
      end
    @campaign_target =
      if @collection
        collection_path(@collection)
      elsif @featured
        product_path(@featured)
      else
        collections_path
      end

    prepare_featured_buy! if @featured
    prepare_landing_media!
  end

  private

  def prepare_featured_buy!
    @featured = current_store.products.active.includes(:product_variants, :translations).find(@featured.id)
    @variants = @featured.product_variants.active.order(:name)
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
      [SIZE_ORDER.index(v[:size].to_s.upcase) || 99, COLOR_ORDER.index(v[:color].to_s) || 99]
    end
  end

  def prepare_landing_media!
    base = "/images/products/essentiel-set"
    front = "#{base}/front.jpg"
    side = "#{base}/side.jpg"
    back = "#{base}/back.jpg"
    details = "#{base}/details.jpg"
    lifestyle = "#{base}/lifestyle.jpg"

    primary = @featured&.image_url.presence
    campaign = @store&.campaign_image_url.presence

    @hero_image = campaign.presence || primary.presence || front
    @story_image = Rails.root.join("public#{lifestyle}").exist? ? lifestyle : front

    @gallery = [
      { label: t("landing.gallery.front"), url: primary.presence || front },
      { label: t("landing.gallery.side"), url: side },
      { label: t("landing.gallery.back"), url: back },
      { label: t("landing.gallery.details"), url: details }
    ]
  end

  SIZE_ORDER = %w[XS S M L XL XXL].freeze
  COLOR_ORDER = ["Rose poudré", "Blush", "Taupe", "Sand", "Noir", "Black", "Ink"].freeze

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
