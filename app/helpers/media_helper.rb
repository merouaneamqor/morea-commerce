module MediaHelper
  def product_image_tag(product, alt: nil, widths: [640, 960, 1280], sizes: "(max-width: 768px) 100vw, 50vw", css_class: "h-full w-full object-cover", loading: "lazy", fetchpriority: nil)
    url = product_image_url(product)
    return placeholder_frame("Image forthcoming") if url.blank?

    if url.start_with?("http")
      object_image_tag(url, alt: alt || product.name, widths: widths, sizes: sizes, css_class: css_class, loading: loading, fetchpriority: fetchpriority)
    else
      image_tag url, alt: alt || product.name, class: css_class, loading: loading, decoding: "async", fetchpriority: fetchpriority
    end
  end

  # Main uploaded image (first in the admin order); nil until one is uploaded
  def product_image_url(product)
    media_url(product.ordered_images.first) if product.images.attached?
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

  def object_image_tag(url, alt:, widths: [640, 960, 1280, 1600], sizes: "(max-width: 768px) 100vw, 50vw", css_class: "h-full w-full object-cover", loading: "lazy", fetchpriority: nil)
    return placeholder_frame("Image forthcoming") if url.blank?

    srcset = widths.map { |w| "#{cdn_image_url(url, width: w)} #{w}w" }.join(", ")
    options = {
      alt: alt,
      srcset: srcset,
      sizes: sizes,
      class: css_class,
      loading: loading,
      decoding: "async"
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

  def preload_hero_image(url)
    return if url.blank?

    if url.to_s.start_with?("http")
      tag.link(
        rel: "preload",
        as: "image",
        href: cdn_image_url(url, width: 1280),
        imagesrcset: [640, 960, 1280].map { |w| "#{cdn_image_url(url, width: w)} #{w}w" }.join(", "),
        imagesizes: "(max-width: 768px) 100vw, 58vw"
      )
    else
      tag.link(rel: "preload", as: "image", href: url)
    end
  end

  def placeholder_frame(text)
    tag.div(class: "flex h-full w-full items-center justify-center bg-stone-deep text-[11px] uppercase tracking-[0.2em] text-ink-faint") { text }
  end

  def money(cents, currency = "MAD")
    "#{(cents.to_i / 100).to_fs(:delimited)} #{currency}"
  end

  def color_hex(name)
    {
      "blush" => "#f8cdd0",
      "rose poudré" => "#d9a8ab",
      "rose poudre" => "#d9a8ab",
      "sand" => "#d6c3b0",
      "taupe" => "#9a8b7a",
      "ink" => "#1a1716",
      "noir" => "#1a1716",
      "black" => "#1a1716",
      "white" => "#faf9f7",
      "rose" => "#e8b4b8",
      "cognac" => "#8b5a3c"
    }[name.to_s.downcase] || "#c4b8b0"
  end
end
