# frozen_string_literal: true

module PixelsHelper
  def pixels_enabled?
    current_store&.pixels_configured?
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
        pixel_event_payload_value: payload.to_json
      }
    )
  end

  def product_pixel_payload(product, quantity: 1)
    {
      content_ids: [ product.id.to_s ],
      content_type: "product",
      content_name: product.name,
      value: pixel_value(product.price_cents) * quantity.to_i,
      currency: current_store.pixel_currency,
      quantity: quantity.to_i
    }
  end

  def cart_pixel_payload(cart)
    items = cart.cart_items.includes(:product)
    {
      content_ids: items.map { |i| i.product_id.to_s },
      content_type: "product",
      value: pixel_value(cart.subtotal_cents),
      currency: current_store.pixel_currency,
      num_items: cart.item_count
    }
  end

  def order_pixel_payload(order)
    {
      content_ids: order.order_items.map { |i| i.product_id.to_s }.compact,
      content_type: "product",
      value: pixel_value(order.total_cents),
      currency: order.currency.to_s.upcase == "DH" ? "MAD" : order.currency.to_s.upcase.presence || current_store.pixel_currency,
      num_items: order.order_items.sum(&:quantity)
    }
  end
end
