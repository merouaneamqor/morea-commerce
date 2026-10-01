# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

class DiscordNotifier
  WEBHOOK_ENV = "DISCORD_ORDERS_WEBHOOK_URL"

  def self.notify_new_order(order)
    new.notify_new_order(order)
  end

  def notify_new_order(order)
    url = ENV[WEBHOOK_ENV].to_s.strip
    if url.blank?
      Rails.logger.info("[DiscordNotifier] Skipping — #{WEBHOOK_ENV} not set")
      return false
    end

    payload = {
      username: "Morea",
      embeds: [ order_embed(order) ]
    }

    post_json(url, payload)
  end

  private

  def order_embed(order)
    items = order.order_items.map do |item|
      line = "• #{item.product_name}"
      line += " — #{item.variant_name}" if item.variant_name.present?
      line += " × #{item.quantity} — #{money(item.total_cents, order.currency)}"
      line
    end.join("\n")

    fields = [
      { name: "Customer", value: order.customer_name.to_s.truncate(256), inline: true },
      { name: "Phone", value: order.customer_phone.to_s.truncate(256), inline: true },
      { name: "City", value: order.customer_city.to_s.truncate(256), inline: true },
      { name: "Address", value: order.customer_address.to_s.truncate(1024) },
      { name: "Items", value: items.presence&.truncate(1024) || "—" },
      { name: "Total", value: money(order.total_cents, order.currency), inline: true },
      { name: "Payment", value: order.payment_method.to_s.upcase.presence || "COD", inline: true }
    ]

    if order.notes.present?
      fields << { name: "Notes", value: order.notes.to_s.truncate(1024) }
    end

    {
      title: "New order #{order.number}",
      url: admin_order_url(order),
      color: 0x9a6f72,
      fields: fields,
      timestamp: order.created_at&.iso8601,
      footer: { text: order.store&.name || "Morea" }
    }
  end

  def money(cents, currency)
    "#{(cents.to_i / 100.0).round} #{currency}"
  end

  def admin_order_url(order)
    host = ENV.fetch("APP_HOST", "localhost:3010")
    protocol = host.include?("localhost") ? "http" : "https"
    "#{protocol}://#{host}/admin/orders/#{order.id}"
  end

  def post_json(url, payload)
    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = 5
    http.read_timeout = 10
    # Local Docker/WSL behind TLS inspection often lacks the corporate CA.
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE if Rails.env.development?

    request = Net::HTTP::Post.new(uri.request_uri)
    request["Content-Type"] = "application/json"
    request.body = payload.to_json

    response = http.request(request)
    unless response.is_a?(Net::HTTPSuccess) || response.code.to_i == 204
      raise "Discord webhook failed: HTTP #{response.code} #{response.body.to_s.truncate(200)}"
    end

    true
  end
end
