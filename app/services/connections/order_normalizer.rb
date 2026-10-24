# frozen_string_literal: true

require "bigdecimal"

module Connections
  class OrderNormalizer
    class Error < StandardError; end
    MAX_CENTS = 2_147_483_647

    def initialize(connection)
      @connection = connection
    end

    def call(payload)
      raise Error, "invalid_payload" unless payload.is_a?(Hash)

      @data = @connection.provider == "youcan" ? payload.fetch("data", {}) : payload
      raise Error, "invalid_payload" unless @data.is_a?(Hash)
      result = send(@connection.provider)
      currency = @data["currency"].to_s.upcase
      expected = @connection.store.currency.to_s.upcase
      expected = "MAD" if expected == "DH"
      raise Error, "currency_mismatch" unless currency == expected && currency == "MAD"
      raise Error, "invalid_lines" unless result[:lines].size.between?(1, 100)

      subtotal = result[:lines].sum { |line| line[:total_cents] }
      total = money(@data["total_price"] || @data["total"])
      raise Error, "totals_mismatch" unless subtotal + result[:shipping_cents] == total
      result.merge(subtotal_cents: subtotal, total_cents: total, currency: @connection.store.currency, discount_cents: 0)
    rescue KeyError, TypeError, NoMethodError
      raise Error, "incomplete_payload"
    end

    private

    def shopify
      raise Error, "unsupported_payment" unless @data["financial_status"] == "pending" && @data["payment_gateway_names"] == [ "Cash on Delivery (COD)" ]
      raise Error, "unsupported_status" if @data["cancelled_at"].present? || @data["fulfillment_status"].present?
      zero!(@data.fetch("total_tax"))
      zero!(@data.fetch("total_discounts"))
      address = @data.fetch("shipping_address")
      lines = @data.fetch("line_items").map do |line|
        raise Error, "unsupported_fulfillment" if line["fulfillment_status"].present? || line["requires_shipping"] == false
        zero!(line.fetch("total_discount", "0"))
        snapshot(line.fetch("name"), line.fetch("quantity"), line.fetch("price"), variant: line["variant_title"])
      end
      contact(address, "address1", "address2").merge(lines: lines, shipping_cents: money(@data.fetch("total_shipping_price_set").fetch("shop_money").fetch("amount")))
    end

    def woocommerce
      raise Error, "unsupported_payment" unless @data["payment_method"] == "cod" && @data["date_paid"].blank? && @data["date_paid_gmt"].blank?
      raise Error, "unsupported_status" unless %w[pending processing on-hold].include?(@data["status"])
      zero!(@data.fetch("total_tax"))
      zero!(@data.fetch("discount_total"))
      raise Error, "unsupported_fees" if @data.fetch("fee_lines", []).any? || @data.fetch("refunds", []).any?
      address = @data.fetch("shipping").merge("phone" => @data.fetch("billing")["phone"])
      lines = @data.fetch("line_items").map do |line|
        quantity = quantity(line.fetch("quantity"))
        total = money(line.fetch("total"))
        raise Error, "unsupported_discount" unless total == money(line.fetch("subtotal"))
        raise Error, "unsupported_precision" unless (total % quantity).zero?
        snapshot(line.fetch("name"), quantity, BigDecimal(total.to_s) / quantity / 100, variant: woo_variant(line))
      end
      contact(address, "address_1", "address_2").merge(lines: lines, shipping_cents: money(@data.fetch("shipping_total")))
    end

    def youcan
      payment = @data.fetch("payment")
      shipping = @data.fetch("shipping")
      raise Error, "unsupported_payment" unless payment["gateway_type"] == 1 && payment.dig("status_object", "slug") == "pending"
      raise Error, "unsupported_status" unless @data.dig("status_object", "slug") == "open" && shipping.dig("status_object", "slug") == "unfulfilled"
      zero!(@data.fetch("vat"))
      raise Error, "unsupported_refund" if @data.fetch("refunds", []).any?
      lines = @data.fetch("variants").map do |line|
        variant = line.fetch("variant")
        snapshot(variant.fetch("product").fetch("name"), line.fetch("quantity"), line.fetch("price"), variant: youcan_variant(variant))
      end
      address = shipping.fetch("address")
      raise Error, "incomplete_payload" unless address.is_a?(Hash)
      contact(address, "first_line", "second_line").merge(lines: lines, shipping_cents: money(shipping.fetch("price")))
    end

    def contact(address, line1, line2)
      raise Error, "unsupported_country" unless address["country_code"] == "MA" || address["country"] == "MA"
      name = address["name"].presence || [ address["first_name"], address["last_name"] ].compact.join(" ")
      fields = { customer_name: name, customer_phone: address["phone"], customer_city: address["city"], customer_address: address[line1], customer_district: address[line2] }
      fields.except(:customer_district).each_value do |value|
        raise Error, "invalid_contact" unless value.is_a?(String) && value.strip.present? && value.length <= 255
      end
      phone = fields[:customer_phone].gsub(/[^\d+]/, "")
      raise Error, "invalid_contact" unless phone.match?(/\A\+?\d{8,15}\z/)
      fields.merge(customer_phone: phone)
    end

    def snapshot(name, count, price, variant: nil)
      raise Error, "invalid_lines" unless name.is_a?(String) && name.present? && name.length <= 255
      count = quantity(count)
      unit = money(price)
      total = unit * count
      raise Error, "money_out_of_range" if total > MAX_CENTS
      { product_name: name, variant_name: variant.to_s.first(255).presence, quantity: count, unit_price_cents: unit, total_cents: total }
    end

    def woo_variant(line)
      metadata = line["meta_data"]
      labels = if metadata.is_a?(Array)
        metadata.first(100).filter_map do |row|
          next unless row.is_a?(Hash) && row["key"].is_a?(String) && !row["key"].start_with?("_")
          key = public_label(row["display_key"] || row["key"])
          value = public_label(row["display_value"] || row["value"])
          next if key.blank? || key.start_with?("_") || value.blank?

          "#{key}: #{value}"
        end.first(16)
      else
        []
      end
      return labels.join(" / ").first(255) if labels.any?

      id = line["variation_id"]
      "Variation ##{id}" if id.is_a?(Integer) && id.positive?
    end

    def youcan_variant(variant)
      variations = variant["variations"]
      labels = if variations.is_a?(Hash)
        variations.first(16).filter_map do |key, value|
          key = public_label(key)
          value = public_label(value)
          next if key.blank? || key == "default" || key.start_with?("_") || value.blank?

          "#{key}: #{value}"
        end
      else
        []
      end
      if labels.empty? && variant["options"].is_a?(Array) && variant["values"].is_a?(Array)
        labels = variant["options"].first(16).zip(variant["values"].first(16)).filter_map do |key, value|
          key = public_label(key)
          value = public_label(value)
          next if key.blank? || key == "default" || key.start_with?("_") || value.blank?

          "#{key}: #{value}"
        end
      end
      return labels.join(" / ").first(255) if labels.any?

      id = public_label(variant["id"])
      "Variant #{id}" if id.present?
    end

    def public_label(value)
      return unless value.is_a?(String) || value.is_a?(Numeric)

      ActionController::Base.helpers.strip_tags(value.to_s).gsub(/[[:cntrl:]]/, " ").squish.first(100)
    end

    def quantity(value)
      raise Error, "invalid_quantity" unless value.is_a?(Integer) && value.between?(1, 10_000)
      value
    end

    def money(value)
      text = value.is_a?(BigDecimal) ? value.to_s("F") : value.to_s
      raise Error, "invalid_money" unless text.match?(/\A\d+(?:\.\d+)?\z/) && text.length <= 30
      cents = BigDecimal(text) * 100
      raise Error, "unsupported_precision" unless cents.frac.zero?
      raise Error, "money_out_of_range" unless cents.between?(0, MAX_CENTS)
      cents.to_i
    end

    def zero!(value)
      raise Error, "unsupported_tax_or_discount" unless money(value).zero?
    end
  end
end
