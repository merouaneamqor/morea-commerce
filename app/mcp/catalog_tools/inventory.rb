# frozen_string_literal: true

module CatalogTools
  module Inventory
    MOVEMENT_FIELDS = <<~GQL.squish
      id productSlug productName size color variantName orderNumber quantity reason note stockAfter createdAt
    GQL

    LEVEL_FIELDS = <<~GQL.squish
      slug name status trackInventory sku size color variantId stock sellableStock lowStock stockValueDh priceDh
    GQL

    SUMMARY_FIELDS = <<~GQL.squish
      trackedProducts untrackedProducts lowStockCount outOfStockCount totalUnits totalStockValueDh threshold
      byReason { reason count quantity }
    GQL

    ADJUST_FIELDS = <<~GQL.squish
      product { #{CatalogExecutor::PRODUCT_FIELDS} }
      movement { #{MOVEMENT_FIELDS} }
      previousStock stock errors
    GQL

    class ListInventory < MCP::Tool
      description "Current on-hand inventory levels for products and active variants. Use lowStockOnly for items at or below the store threshold. When a product has variants, each active variant is a row; product.stock is ignored for sellable stock."
      input_schema(
        properties: {
          slug: { type: "string" },
          status: { type: "string", enum: %w[draft active archived] },
          lowStockOnly: { type: "boolean" },
          limit: { type: "integer", description: "1-200, default 50" }
        }
      )

      def self.call(server_context:, slug: nil, status: nil, lowStockOnly: nil, limit: nil)
        CatalogExecutor.call(
          store: server_context.fetch(:store),
          include_covers: false,
          query: <<~GQL,
            query($slug: String, $status: String, $lowStockOnly: Boolean, $limit: Int) {
              inventoryLevels(slug: $slug, status: $status, lowStockOnly: $lowStockOnly, limit: $limit) {
                #{LEVEL_FIELDS}
              }
            }
          GQL
          variables: { slug: slug, status: status, lowStockOnly: lowStockOnly, limit: limit }.compact
        )
      end
    end

    class ListLowStock < MCP::Tool
      description "Products and variants at or below the store low-stock threshold. Same rows as list_inventory with lowStockOnly: true."
      input_schema(
        properties: {
          status: { type: "string", enum: %w[draft active archived] },
          limit: { type: "integer", description: "1-200, default 50" }
        }
      )

      def self.call(server_context:, status: nil, limit: nil)
        ListInventory.call(server_context: server_context, status: status, lowStockOnly: true, limit: limit)
      end
    end

    class InventorySummary < MCP::Tool
      description "Store-wide inventory snapshot: tracked vs untracked products, low/out-of-stock counts, total units and stock value, plus movement totals by reason. Optional since/until (YYYY-MM-DD) filter the byReason ledger window."
      input_schema(
        properties: {
          since: { type: "string", description: "YYYY-MM-DD" },
          until: { type: "string", description: "YYYY-MM-DD" }
        }
      )

      def self.call(server_context:, since: nil, until: nil)
        finish = binding.local_variable_get(:until)
        CatalogExecutor.call(
          store: server_context.fetch(:store),
          include_covers: false,
          query: <<~GQL,
            query($since: ISO8601Date, $until: ISO8601Date) {
              inventorySummary(since: $since, until: $until) { #{SUMMARY_FIELDS} }
            }
          GQL
          variables: { since: since, until: finish }.compact
        )
      end
    end

    class ListInventoryMovements < MCP::Tool
      description "Inventory ledger history: signed quantity, reason, note, optional order number, and variant. Reasons include manual_adjustment, received, damaged, correction, order_confirmed, order_cancelled, order_returned, order_edited."
      input_schema(
        properties: {
          slug: { type: "string" },
          reason: {
            type: "string",
            enum: %w[manual_adjustment received damaged correction order_confirmed order_cancelled order_returned order_edited]
          },
          since: { type: "string", description: "YYYY-MM-DD" },
          until: { type: "string", description: "YYYY-MM-DD" },
          limit: { type: "integer", description: "1-200, default 50" }
        }
      )

      def self.call(server_context:, slug: nil, reason: nil, since: nil, until: nil, limit: nil)
        finish = binding.local_variable_get(:until)
        CatalogExecutor.call(
          store: server_context.fetch(:store),
          include_covers: false,
          query: <<~GQL,
            query($slug: String, $reason: String, $since: ISO8601Date, $until: ISO8601Date, $limit: Int) {
              inventoryMovements(slug: $slug, reason: $reason, since: $since, until: $until, limit: $limit) {
                #{MOVEMENT_FIELDS}
              }
            }
          GQL
          variables: { slug: slug, reason: reason, since: since, until: finish, limit: limit }.compact
        )
      end
    end

    class AdjustStock < MCP::Tool
      description "Apply a signed stock delta (+ receive / - damage) and write an inventory movement. Target a variant with size+color or variantId when the product has variants. Reasons for writes: manual_adjustment, received, damaged, correction. Stock cannot go below zero."
      input_schema(
        properties: {
          slug: { type: "string" },
          quantity: { type: "integer", description: "Signed delta, non-zero" },
          reason: { type: "string", enum: %w[manual_adjustment received damaged correction] },
          note: { type: "string" },
          size: { type: "string" },
          color: { type: "string" },
          variantId: { type: "string" }
        },
        required: %w[slug quantity reason]
      )

      def self.call(slug:, quantity:, reason:, server_context:, note: nil, size: nil, color: nil, variantId: nil)
        CatalogExecutor.call(
          store: server_context.fetch(:store),
          query: <<~GQL,
            mutation(
              $slug: String!, $quantity: Int!, $reason: String!, $note: String,
              $size: String, $color: String, $variantId: ID
            ) {
              adjustStock(
                slug: $slug, quantity: $quantity, reason: $reason, note: $note,
                size: $size, color: $color, variantId: $variantId
              ) { #{ADJUST_FIELDS} }
            }
          GQL
          variables: {
            slug: slug, quantity: quantity, reason: reason, note: note,
            size: size, color: color, variantId: variantId
          }.compact
        )
      end
    end

    class SetStock < MCP::Tool
      description "Set absolute on-hand stock and write a ledger movement for the delta. Prefer adjust_stock for receives/damage. Default reason is correction. Target variants with size+color or variantId."
      input_schema(
        properties: {
          slug: { type: "string" },
          stock: { type: "integer", description: "Absolute on-hand quantity, >= 0" },
          reason: { type: "string", enum: %w[manual_adjustment received damaged correction] },
          note: { type: "string" },
          size: { type: "string" },
          color: { type: "string" },
          variantId: { type: "string" }
        },
        required: %w[slug stock]
      )

      def self.call(slug:, stock:, server_context:, reason: nil, note: nil, size: nil, color: nil, variantId: nil)
        CatalogExecutor.call(
          store: server_context.fetch(:store),
          query: <<~GQL,
            mutation(
              $slug: String!, $stock: Int!, $reason: String, $note: String,
              $size: String, $color: String, $variantId: ID
            ) {
              setStock(
                slug: $slug, stock: $stock, reason: $reason, note: $note,
                size: $size, color: $color, variantId: $variantId
              ) { #{ADJUST_FIELDS} }
            }
          GQL
          variables: {
            slug: slug, stock: stock, reason: reason, note: note,
            size: size, color: color, variantId: variantId
          }.compact
        )
      end
    end
  end
end
