module MediaHelper
  def product_image_tag(product, alt: nil, widths: [ 640, 960, 1280 ], sizes: "(max-width: 768px) 100vw, 50vw", css_class: "h-full w-full object-cover", loading: "lazy", fetchpriority: nil)
    url = product_image_url(product)
    return placeholder_frame("Image forthcoming") if url.blank?

    if url.start_with?("http")
      object_image_tag(url, alt: alt || product.name, widths: widths, sizes: sizes, css_class: css_class, loading: loading, fetchpriority: fetchpriority)
    else
      image_tag url, alt: alt || product.name, class: css_class, loading: loading, decoding: fetchpriority.to_s == "high" ? "sync" : "async", fetchpriority: fetchpriority
    end
  end

  # Main uploaded image (first in the admin order); nil until one is uploaded
  def product_image_url(product)
    return media_url(product.ordered_images.first) if product.images.attached?

    product.image_url.presence # the picture of an imported product stays at its store
  end

  # Second uploaded image, shown on card hover
  def product_alt_image_url(product)
    second = product.ordered_images.second if product.images.attached?
    media_url(second) if second
  end

  # Delivery URL for an uploaded image, with its batch edits (see MediaUrl)
  def media_url(attachment)
    MediaUrl.for(attachment, store: respond_to?(:current_store, true) ? current_store : nil)
  end

  # Cover uploaded in admin (collection tiles fall back to a product photo)
  def collection_cover_url(collection)
    media_url(collection.image) if collection.image.attached?
  end

  def object_image_tag(url, alt:, widths: [ 640, 960, 1280, 1600 ], sizes: "(max-width: 768px) 100vw, 50vw", css_class: "h-full w-full object-cover", loading: "lazy", fetchpriority: nil)
    return placeholder_frame("Image forthcoming") if url.blank?

    srcset = widths.map { |w| "#{cdn_image_url(url, width: w)} #{w}w" }.join(", ")
    options = {
      alt: alt,
      srcset: srcset,
      sizes: sizes,
      class: css_class,
      loading: loading,
      decoding: fetchpriority.to_s == "high" ? "sync" : "async"
    }
    options[:fetchpriority] = fetchpriority if fetchpriority

    image_tag cdn_image_url(url, width: widths[1] || 960), **options
  end

  def cdn_image_url(url, width:, quality: 75)
    return url if url.blank?
    return MediaUrl.sized(url, width: width) if url.include?("res.cloudinary.com/")
    return url unless url.include?("images.unsplash.com")

    uri = URI.parse(url)
    params = URI.decode_www_form(uri.query || "").to_h
    params["auto"] = "format"
    params["fit"] = "crop"
    params["w"] = width.to_s
    params["q"] = quality.to_s
    uri.query = URI.encode_www_form(params)
    uri.to_s
  rescue URI::InvalidURIError
    url
  end

  def preload_hero_image(url, widths: [ 640, 960, 1440, 1920 ], sizes: "100vw")
    return if url.blank?

    if url.to_s.start_with?("http")
      tag.link(
        rel: "preload",
        as: "image",
        href: cdn_image_url(url, width: widths[1] || widths.first),
        imagesrcset: widths.map { |w| "#{cdn_image_url(url, width: w)} #{w}w" }.join(", "),
        imagesizes: sizes,
        fetchpriority: "high"
      )
    else
      tag.link(rel: "preload", as: "image", href: url, fetchpriority: "high")
    end
  end

  def page_lcp_preload(section)
    return if section.blank?

    case section.kind
    when "hero"
      preload_hero_image(section.image_src, widths: [ 640, 960, 1440, 1920 ], sizes: "100vw") if section.image_src.present?
    when "image_with_text"
      preload_hero_image(section.image_src, widths: [ 640, 960, 1280 ], sizes: "(max-width: 768px) 100vw, 50vw") if section.image_src.present?
    when "rich_text"
      tag.link(rel: "preload", as: "image", href: cdn_image_url(section.image_src, width: 1600), fetchpriority: "high") if section.image_src.present?
    when "featured_collection"
      product = section.products.first
      url = product_image_url(product) if product
      preload_hero_image(url, widths: [ 640, 960, 1280 ], sizes: "(max-width: 768px) 50vw, 25vw") if url.present?
    end
  end

  def placeholder_frame(text)
    tag.div(class: "placeholder-frame", role: "img", aria: { label: text })
  end

  def money(cents, currency = "MAD")
    "#{(cents.to_i / 100).to_fs(:delimited)} #{currency}"
  end

  def color_hex(_name = nil, stored: nil)
    ProductVariant.normalize_hex(stored) || ProductVariant::PLACEHOLDER_HEX
  end
end
