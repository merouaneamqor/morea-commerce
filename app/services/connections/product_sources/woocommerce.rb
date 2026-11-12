# frozen_string_literal: true

module Connections
  module ProductSources
    # WooCommerce products through the REST API (wc/v3), with the store's consumer key and secret (read access is enough).
    # A variable product is read together with its variations, each with its own price and stock.
    class Woocommerce
      PER_PAGE = 100
      MAX_PAGES = 200
      STATUSES = { "publish" => "active", "draft" => "draft", "pending" => "draft", "private" => "draft", "trash" => "archived" }.freeze

      def initialize(connection:, transport: nil)
        @connection = connection
        @transport = transport
      end

      def each_item
        credentials = @connection.api_credentials
        key = credentials["consumer_key"].to_s
        secret = credentials["consumer_secret"].to_s
        raise Error.new("credentials_missing") if key.blank? || secret.blank?
        raise Error.new("disconnected") unless @connection.active?
        raise Error.new("unsafe_domain") unless ProductSources.public_host?(@connection.external_domain)

        @auth = [ key, secret ]
        page = 1
        loop do
          rows, response = get("products", page: page, per_page: PER_PAGE, status: "any")
          raise Error.new("invalid_response") unless rows.is_a?(Array)

          rows.each { |row| yield item(row) }
          total_pages = response["X-WP-TotalPages"].to_i
          page += 1
          break if rows.empty? || (total_pages.positive? ? page > total_pages : rows.size < PER_PAGE) || page > MAX_PAGES
        end
      end

      private

      def get(path, params = {})
        uri = URI("https://#{@connection.external_domain}/wp-json/wc/v3/#{path}")
        uri.query = URI.encode_www_form(params) if params.any?
        ProductSources::Http.get_json(uri, headers: { "Accept" => "application/json" }, basic_auth: @auth, transport: @transport)
      end

      def item(row)
        variable = row["type"] == "variable"
        variants = variable ? variations(row.fetch("id")) : []
        prices = variants.filter_map(&:price_cents)
        price = ProductSources.cents(row["price"].presence || row["regular_price"]) || prices.min
        compare = ProductSources.cents(row["regular_price"]) if row["on_sale"] == true
        managed = row["manage_stock"] == true
        Item.new(
          external_id: row.fetch("id").to_s, name: row["name"].to_s.strip.presence || "Untitled", status: STATUSES.fetch(row["status"].to_s, "draft"),
          price_cents: variable ? prices.min || price : price, compare_at_cents: compare, sku: row["sku"].presence, image_url: Array(row["images"]).first&.dig("src"),
          track_inventory: managed || variable, stock: managed && !variable ? row["stock_quantity"].to_i.clamp(0, 2_000_000_000) : nil, variants: variants
        )
      end

      def variations(product_id)
        rows, = get("products/#{product_id}/variations", per_page: PER_PAGE)
        raise Error.new("invalid_response") unless rows.is_a?(Array)

        rows.map do |row|
          options = Array(row["attributes"]).map { |attribute| [ attribute["name"].to_s, attribute["option"].to_s ] }
          managed = row["manage_stock"] == true
          Variant.new(external_id: row.fetch("id").to_s, name: options.map(&:last).reject(&:blank?).join(" / ").presence || "Variation #{row['id']}", sku: row["sku"].presence,
                      price_cents: ProductSources.cents(row["price"].presence || row["regular_price"]), stock: managed ? row["stock_quantity"].to_i.clamp(0, 2_000_000_000) : nil,
                      options: options, active: row["status"].to_s == "publish")
        end
      end
    end
  end
end
