# frozen_string_literal: true

module Connections
  module ProductSources
    # Shopify products through the Admin GraphQL API, with the shop's own OAuth token (scope read_products, already part of
    # the permissions Seallo asks for). Variants carry their own price and stock.
    class Shopify
      PAGE = 50
      QUERY = <<~GRAPHQL
        query($cursor: String) {
          products(first: #{PAGE}, after: $cursor) {
            pageInfo { hasNextPage endCursor }
            nodes {
              id title status tracksInventory totalInventory
              featuredImage { url }
              variants(first: 100) { nodes { id title sku price compareAtPrice inventoryQuantity selectedOptions { name value } } }
            }
          }
        }
      GRAPHQL
      STATUSES = { "ACTIVE" => "active", "DRAFT" => "draft", "ARCHIVED" => "archived" }.freeze

      def initialize(connection:, transport: nil)
        @api = Connections::ShopifyApi.new(connection: connection, transport: transport)
      end

      def each_item
        cursor = nil
        loop do
          data = graphql(cursor)
          page = data["products"]
          raise Error.new("invalid_response") unless page.is_a?(Hash) && page["nodes"].is_a?(Array)

          page["nodes"].each { |node| yield item(node) }
          break unless page.dig("pageInfo", "hasNextPage") == true

          cursor = page.dig("pageInfo", "endCursor")
          raise Error.new("invalid_response") if cursor.blank?
        end
      end

      private

      def graphql(cursor)
        @api.graphql(query: QUERY, variables: { cursor: cursor })
      rescue Connections::ShopifyApi::Error => error
        raise Error.new(error.code)
      end

      def item(node)
        variants = Array(node.dig("variants", "nodes")).map { |variant| variant_item(variant) }
        # A product with no option is a single "Default Title" variant: its price and stock are the product's own.
        single = variants.one? && variants.first.options.all? { |_name, value| value == "Default Title" }
        prices = variants.filter_map(&:price_cents)
        tracked = node["tracksInventory"] == true
        Item.new(
          external_id: node.fetch("id").to_s, name: node["title"].to_s.strip.presence || "Untitled", status: STATUSES.fetch(node["status"].to_s, "draft"),
          price_cents: prices.min, compare_at_cents: ProductSources.cents(Array(node.dig("variants", "nodes")).first&.dig("compareAtPrice")),
          sku: single ? variants.first.sku : nil, image_url: node.dig("featuredImage", "url"), track_inventory: tracked,
          stock: tracked ? node["totalInventory"].to_i.clamp(0, 2_000_000_000) : nil, variants: single ? [] : variants
        )
      end

      def variant_item(variant)
        options = Array(variant["selectedOptions"]).map { |option| [ option["name"].to_s, option["value"].to_s ] }
        name = options.map(&:last).reject(&:blank?).join(" / ").presence || variant["title"].to_s.presence || "Default"
        Variant.new(external_id: variant.fetch("id").to_s, name: name, sku: variant["sku"].presence, price_cents: ProductSources.cents(variant["price"]),
                    stock: variant["inventoryQuantity"].nil? ? nil : variant["inventoryQuantity"].to_i.clamp(0, 2_000_000_000), options: options, active: true)
      end
    end
  end
end
