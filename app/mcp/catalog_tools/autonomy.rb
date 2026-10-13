# frozen_string_literal: true

module CatalogTools
  module Autonomy
    CHANGESET_FIELDS = <<~GQL.squish
      token status summary maxLevel operations preview results verification
      appliedAt verifiedAt rolledBackAt
    GQL

    AUDIT_FIELDS = <<~GQL.squish
      summary { productCount collectionCount issueCount bySeverity byCode autoFixableCount }
      issues { severity code entityType entitySlug locale message suggestion autoFixable level }
    GQL

    class GetStoreProfile < MCP::Tool
      description "Brand guidelines, locales, pricing rules, naming conventions, and approval levels for this store. Use before planning catalog changes."

      def self.call(server_context:)
        CatalogExecutor.call(
          store: server_context.fetch(:store),
          query: "query { storeProfile }",
          include_covers: false
        )
      end
    end

    class GetFullCatalog < MCP::Tool
      description "Paginated catalog dump: products (with variants, images, translations, collections) and all collections. Use for store-wide inspection before an audit or change plan."
      input_schema(
        properties: {
          page: { type: "integer", description: "1-based page, default 1" },
          perPage: { type: "integer", description: "1-100, default 50" },
          status: { type: "string", enum: %w[draft active archived] }
        }
      )

      def self.call(server_context:, page: nil, perPage: nil, status: nil)
        CatalogExecutor.call(
          store: server_context.fetch(:store),
          include_covers: false,
          query: <<~GQL,
            query($page: Int, $perPage: Int, $status: String) {
              fullCatalog(page: $page, perPage: $perPage, status: $status) {
                page perPage productTotal collectionTotal hasMoreProducts
                products { #{CatalogExecutor::PRODUCT_FIELDS} }
                collections { #{CatalogExecutor::COLLECTION_FIELDS} }
              }
            }
          GQL
          variables: { page: page, perPage: perPage, status: status }.compact
        )
      end
    end

    class AuditStore < MCP::Tool
      description "Prioritized store audit: missing descriptions/translations/images/SEO, duplicate products, bad prices, inventory issues, empty or overlapping collections. Returns actionable issues with autoFixable and approval level."
      input_schema(
        properties: {
          status: { type: "string", enum: %w[draft active archived] },
          limit: { type: "integer", description: "Max products to scan, default 500, max 2000" }
        }
      )

      def self.call(server_context:, status: nil, limit: nil)
        CatalogExecutor.call(
          store: server_context.fetch(:store),
          include_covers: false,
          query: <<~GQL,
            query($status: String, $limit: Int) {
              auditStore(status: $status, limit: $limit) { #{AUDIT_FIELDS} }
            }
          GQL
          variables: { status: status, limit: limit }.compact
        )
      end
    end

    class GetProductSchema < MCP::Tool
      description "Editable product fields, locales, constraints, and approval levels. Call before building update or changeset operations."

      def self.call(server_context:)
        CatalogExecutor.call(
          store: server_context.fetch(:store),
          query: "query { productSchema }",
          include_covers: false
        )
      end
    end

    class ValidateProduct < MCP::Tool
      description "Validate one product for required content, translations, SEO, and pricing rules. Returns errors and audit issues for that slug."
      input_schema(
        properties: { slug: { type: "string" } },
        required: [ "slug" ]
      )

      def self.call(slug:, server_context:)
        CatalogExecutor.call(
          store: server_context.fetch(:store),
          include_covers: false,
          query: <<~GQL,
            query($slug: String!) {
              validateProduct(slug: $slug) {
                ok slug errors
                issues { severity code entityType entitySlug locale message suggestion autoFixable level }
                schema
              }
            }
          GQL
          variables: { slug: slug }
        )
      end
    end

    class SuggestCollectionStructure < MCP::Tool
      description "Recommend collection creates, assignments for uncategorized products, and merges for heavily overlapping collections."
      input_schema(
        properties: {
          limit: { type: "integer", description: "Max suggestions, default 20" }
        }
      )

      def self.call(server_context:, limit: nil)
        CatalogExecutor.call(
          store: server_context.fetch(:store),
          include_covers: false,
          query: <<~GQL,
            query($limit: Int) {
              suggestCollectionStructure(limit: $limit) {
                summary
                suggestions { action slug keepSlug dropSlug reason translations productSlugs level }
              }
            }
          GQL
          variables: { limit: limit }.compact
        )
      end
    end

    class PreviewChangeset < MCP::Tool
      description "Build a change plan without writing. operations is an array of {type, ...}. Types: create_product, update_product, set_product_collections, create_collection, update_collection, set_collection_products, delete_product, delete_collection, update_store_profile, adjust_stock, set_stock. Returns a token, per-op approval level, and diffs."
      input_schema(
        properties: {
          operations: {
            type: "array",
            items: { type: "object" },
            description: "Each op needs type. create_product: priceDh + translations. update_product: slug + attrs. adjust_stock: slug + quantity + reason. set_stock: slug + stock. set_product_collections: slug + collectionSlugs. create_collection: translations (+ slug, productSlugs). deletes need confirm: true."
          },
          summary: { type: "string" }
        },
        required: [ "operations" ]
      )

      def self.call(operations:, server_context:, summary: nil)
        CatalogExecutor.call(
          store: server_context.fetch(:store),
          include_covers: false,
          query: <<~GQL,
            mutation($operations: JSON!, $summary: String) {
              previewChangeset(operations: $operations, summary: $summary) {
                changeset { #{CHANGESET_FIELDS} }
                errors
              }
            }
          GQL
          variables: { operations: operations, summary: summary }.compact
        )
      end
    end

    class ApplyChangeset < MCP::Tool
      description "Apply a previewed changeset by token. Level 1 ops apply by default. Level 2 (prices, slugs, structural collection changes) needs approveLevel2: true. Level 3 (deletes) needs approveLevel3: true and confirm on each delete op."
      input_schema(
        properties: {
          token: { type: "string" },
          approveLevel2: { type: "boolean" },
          approveLevel3: { type: "boolean" }
        },
        required: [ "token" ]
      )

      def self.call(token:, server_context:, approveLevel2: false, approveLevel3: false)
        CatalogExecutor.call(
          store: server_context.fetch(:store),
          include_covers: false,
          query: <<~GQL,
            mutation($token: String!, $approveLevel2: Boolean, $approveLevel3: Boolean) {
              applyChangeset(token: $token, approveLevel2: $approveLevel2, approveLevel3: $approveLevel3) {
                changeset { #{CHANGESET_FIELDS} }
                errors
              }
            }
          GQL
          variables: { token: token, approveLevel2: approveLevel2, approveLevel3: approveLevel3 }
        )
      end
    end

    class VerifyChangeset < MCP::Tool
      description "Re-read saved catalog data after apply_changeset and report any operations that did not stick."
      input_schema(
        properties: { token: { type: "string" } },
        required: [ "token" ]
      )

      def self.call(token:, server_context:)
        CatalogExecutor.call(
          store: server_context.fetch(:store),
          include_covers: false,
          query: <<~GQL,
            mutation($token: String!) {
              verifyChangeset(token: $token) {
                changeset { #{CHANGESET_FIELDS} }
                errors
              }
            }
          GQL
          variables: { token: token }
        )
      end
    end

    class RollbackChangeset < MCP::Tool
      description "Restore previous values from an applied changeset when snapshots allow it. Deletes cannot be recreated automatically."
      input_schema(
        properties: { token: { type: "string" } },
        required: [ "token" ]
      )

      def self.call(token:, server_context:)
        CatalogExecutor.call(
          store: server_context.fetch(:store),
          include_covers: false,
          query: <<~GQL,
            mutation($token: String!) {
              rollbackChangeset(token: $token) {
                changeset { #{CHANGESET_FIELDS} }
                errors
              }
            }
          GQL
          variables: { token: token }
        )
      end
    end
  end
end
