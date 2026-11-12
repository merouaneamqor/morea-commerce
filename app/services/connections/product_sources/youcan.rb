# frozen_string_literal: true

module Connections
  module ProductSources
    # YouCan products through the Seller API (https://api.youcan.shop), with the store's access token.
    # NOTE: written from YouCan's public API description and exercised with fixtures only; it has not been run against a
    # real YouCan store. Every field is read defensively (several names are accepted), and anything unexpected raises
    # `invalid_response` rather than importing a wrong product.
    class Youcan
      HOST = "api.youcan.shop"
      MAX_PAGES = 200
      INACTIVE = %w[draft inactive hidden disabled archived].freeze

      def initialize(connection:, transport: nil)
        @connection = connection
        @transport = transport
      end

      def each_item
        token = @connection.api_credentials["access_token"].to_s
        raise Error.new("credentials_missing") if token.blank?
        raise Error.new("disconnected") unless @connection.active?

        page = 1
        loop do
          body, = get(token, page)
          rows = body.is_a?(Hash) ? body["data"] : nil
          raise Error.new("invalid_response") unless rows.is_a?(Array)

          rows.each { |row| yield item(row) }
          last = body.dig("meta", "pagination", "total_pages") || body.dig("meta", "last_page")
          page += 1
          break if rows.empty? || (last && page > last.to_i) || page > MAX_PAGES
        end
      end

      private

      def get(token, page)
        uri = URI("https://#{HOST}/products")
        uri.query = URI.encode_www_form(page: page, limit: 100)
        ProductSources::Http.get_json(uri, headers: { "Authorization" => "Bearer #{token}", "Accept" => "application/json" }, transport: @transport)
      end

      def item(row)
        variants = Array(row["variants"]).map { |variant| variant_item(variant) }
        # A product without variations has a single variant carrying its price and stock.
        single = variants.size <= 1 && variants.first&.options.blank?
        prices = variants.filter_map(&:price_cents)
        stock = row["inventory"].nil? ? (single ? variants.first&.stock : nil) : row["inventory"].to_i.clamp(0, 2_000_000_000)
        Item.new(
          external_id: row.fetch("id").to_s, name: row["name"].to_s.strip.presence || "Untitled", status: status(row),
          price_cents: ProductSources.cents(row["price"]) || prices.min, compare_at_cents: ProductSources.cents(row["compare_at_price"]),
          sku: row["sku"].presence || (single ? variants.first&.sku : nil), image_url: image(row), track_inventory: !stock.nil?, stock: stock,
          variants: single ? [] : variants
        )
      end

      def variant_item(variant)
        options = variations(variant["variations"])
        Variant.new(external_id: variant.fetch("id").to_s, name: options.map(&:last).reject(&:blank?).join(" / ").presence || "Default", sku: variant["sku"].presence,
                    price_cents: ProductSources.cents(variant["price"]), stock: variant["inventory"].nil? ? nil : variant["inventory"].to_i.clamp(0, 2_000_000_000),
                    options: options, active: true)
      end

      # {"Size" => "M"} or [{"name" => "Size", "value" => "M"}]
      def variations(raw)
        case raw
        when Hash then raw.map { |name, value| [ name.to_s, value.to_s ] }
        when Array then raw.map { |entry| [ entry["name"].to_s, entry["value"].to_s ] if entry.is_a?(Hash) }.compact
        else []
        end
      end

      def status(row)
        return "draft" if row["is_active"] == false || row["visibility"] == false
        return "draft" if INACTIVE.include?(row["status"].to_s.downcase)

        "active"
      end

      def image(row)
        first = Array(row["images"]).first
        (first.is_a?(Hash) ? first["url"] : first).presence || row["thumbnail"].presence
      end
    end
  end
end
