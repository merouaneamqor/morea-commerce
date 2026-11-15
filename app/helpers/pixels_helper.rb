# frozen_string_literal: true

module PixelsHelper
  def pixels_enabled?
    current_store&.pixels_configured? && measurement_allowed?
  end

  def pixel_value(cents)
    (cents.to_i / 100.0).round(2)
  end

  def pixel_event_tag(name, payload = {})
    return unless pixels_enabled?

    tag.div(
      "",
      class: "hidden",
      data: {
        controller: "pixel-event",
        pixel_event_name_value: name,
        pixel_event_payload_value: payload
      }
    )
  end

  # Purchase confirmation sets @pixel_purchase; Advanced Matching must be on the
  # first fbq('init') call in <head>, so read the order from assigns directly.
  def meta_pixel_advanced_matching
    return {} unless pixels_enabled?
    return {} unless defined?(@pixel_purchase) && @pixel_purchase
    return {} unless defined?(@order) && @order

    order_pixel_user_data(@order)
  end

  def product_content_id(product, variant: nil)
    if variant&.sku.present?
      variant.sku.to_s
    elsif product.sku.present?
      product.sku.to_s
    else
      product.slug.to_s
    end
  end

  def product_pixel_payload(product, quantity: 1, variant: nil)
    qty = [ quantity.to_i, 1 ].max
    unit = pixel_value(variant&.unit_price_cents || product.price_cents)
    content_id = product_content_id(product, variant: variant)
    category = product.collections.map(&:name).compact_blank.first

    {
      content_ids: [ content_id ],
      content_type: "product",
      content_name: product.name,
      content_category: category,
      contents: [
        {
          id: content_id,
          quantity: qty,
          item_price: unit
        }
      ],
      value: (unit * qty).round(2),
      currency: current_store.pixel_currency,
      quantity: qty,
      num_items: qty
    }.compact
  end

  def cart_pixel_payload(cart)
    items = cart.cart_items.includes(:product, :product_variant)
    contents = items.filter_map do |item|
      product = item.product
      next unless product

      unit = pixel_value(item.product_variant&.unit_price_cents || product.price_cents)
      {
        id: product_content_id(product, variant: item.product_variant),
        quantity: item.quantity.to_i,
        item_price: unit
      }
    end

    {
      content_ids: contents.map { |row| row[:id] },
      content_type: "product",
      contents: contents,
      value: pixel_value(cart.subtotal_cents),
      currency: current_store.pixel_currency,
      num_items: cart.item_count,
      quantity: cart.item_count
    }
  end

  def order_pixel_payload(order)
    items = order.order_items.includes(:product)
    contents = items.filter_map do |item|
      product = item.product
      content_id = product ? product_content_id(product) : item.product_slug.presence || item.product_name.to_s
      next if content_id.blank?

      {
        id: content_id.to_s,
        quantity: item.quantity.to_i,
        item_price: pixel_value(item.unit_price_cents)
      }
    end

    currency = order.currency.to_s.upcase == "DH" ? "MAD" : order.currency.to_s.upcase.presence || current_store.pixel_currency

    {
      content_ids: contents.map { |row| row[:id] },
      content_type: "product",
      contents: contents,
      value: pixel_value(order.total_cents),
      currency: currency,
      num_items: order.order_items.sum(&:quantity),
      quantity: order.order_items.sum(&:quantity),
      order_id: order.number.to_s,
      event_id: "purchase-#{order.number}",
      delivery_city: order.customer_city.to_s.presence
    }.compact
  end

  def order_pixel_user_data(order)
    name_parts = order.customer_name.to_s.strip.split(/\s+/, 2)
    phone = order.customer_phone.to_s.gsub(/[^\d+]/, "")
    {
      ph: phone.presence,
      fn: name_parts[0].presence&.downcase,
      ln: name_parts[1].presence&.downcase,
      ct: order.customer_city.to_s.downcase.presence,
      st: order.customer_district.to_s.downcase.presence,
      country: "ma",
      external_id: order.number.to_s
    }.compact
  end

  def collection_pixel_payload(collection, products: [])
    ids = Array(products).first(20).map { |product| product_content_id(product) }
    {
      content_ids: ids,
      content_type: "product_group",
      content_name: collection.name,
      content_category: collection.name,
      currency: current_store.pixel_currency,
      num_items: ids.size
    }
  end

  def search_pixel_payload(query, products: [], total_count: nil)
    ids = Array(products).first(20).map { |product| product_content_id(product) }
    {
      search_string: query.to_s,
      content_ids: ids,
      content_type: "product",
      currency: current_store.pixel_currency,
      num_items: total_count || ids.size
    }
  end
end
