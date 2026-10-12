# frozen_string_literal: true

module Types
  module Autonomy
    class AuditIssueType < BaseObject
      field :severity, String, null: false
      field :code, String, null: false
      field :entity_type, String, null: false
      field :entity_slug, String, null: true
      field :locale, String, null: true
      field :message, String, null: false
      field :suggestion, String, null: false
      field :auto_fixable, Boolean, null: false
      field :level, Integer, null: false
    end

    class AuditSummaryType < BaseObject
      field :product_count, Integer, null: false
      field :collection_count, Integer, null: false
      field :issue_count, Integer, null: false
      field :by_severity, GraphQL::Types::JSON, null: false
      field :by_code, GraphQL::Types::JSON, null: false
      field :auto_fixable_count, Integer, null: false
    end

    class AuditReportType < BaseObject
      field :summary, AuditSummaryType, null: false
      field :issues, [ AuditIssueType ], null: false
    end

    class FullCatalogType < BaseObject
      field :page, Integer, null: false
      field :per_page, Integer, null: false
      field :product_total, Integer, null: false
      field :collection_total, Integer, null: false
      field :has_more_products, Boolean, null: false
      field :products, [ ProductType ], null: false
      field :collections, [ CollectionType ], null: false
    end

    class ValidateProductResultType < BaseObject
      field :ok, Boolean, null: false
      field :slug, String, null: true
      field :errors, [ String ], null: false
      field :issues, [ AuditIssueType ], null: false
      field :schema, GraphQL::Types::JSON, null: false
    end

    class CollectionSuggestionType < BaseObject
      field :action, String, null: false
      field :slug, String, null: true
      field :keep_slug, String, null: true
      field :drop_slug, String, null: true
      field :reason, String, null: false
      field :translations, GraphQL::Types::JSON, null: true
      field :product_slugs, [ String ], null: true
      field :level, Integer, null: false
    end

    class CollectionSuggestionReportType < BaseObject
      field :summary, GraphQL::Types::JSON, null: false
      field :suggestions, [ CollectionSuggestionType ], null: false
    end

    class ChangesetType < BaseObject
      field :token, String, null: false
      field :status, String, null: false
      field :summary, String, null: true
      field :max_level, Integer, null: false
      field :operations, GraphQL::Types::JSON, null: false
      field :preview, GraphQL::Types::JSON, null: false
      field :results, GraphQL::Types::JSON, null: false
      field :verification, GraphQL::Types::JSON, null: false
      field :applied_at, String, null: true
      field :verified_at, String, null: true
      field :rolled_back_at, String, null: true
    end

    class ChangesetPayloadType < BaseObject
      field :changeset, ChangesetType, null: true
      field :errors, [ String ], null: false
    end
  end
end
