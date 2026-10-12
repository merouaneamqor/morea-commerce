# frozen_string_literal: true

module Types
  module Builders
    class PreviewUrlType < BaseObject
      field :locale, String, null: false
      field :url, String, null: false
    end

    class SectionType < BaseObject
      graphql_name "BuilderSection"
      field :id, ID, null: true
      field :kind, String, null: false
      field :label, String, null: false
      field :position, Integer, null: false
      field :visible, Boolean, null: false
      field :image_url, String, null: true
      field :image_src, String, null: true
      field :link, String, null: true
      field :collection_slug, String, null: true
      field :limit, Integer, null: true
      field :image_position, String, null: true
      field :translations, [ Storefront::SectionCopyType ], null: false
    end

    class HomeLayoutType < BaseObject
      field :surface, String, null: false
      field :using_defaults, Boolean, null: false
      field :preview_urls, [ PreviewUrlType ], null: false
      field :announcement, String, null: true
      field :section_schema, GraphQL::Types::JSON, null: false
      field :sections, [ SectionType ], null: false
    end

    class LandingPageType < BaseObject
      field :slug, String, null: false
      field :template, String, null: false
      field :published, Boolean, null: false
      field :preview_urls, [ PreviewUrlType ], null: false
      field :translations, [ Storefront::PageCopyType ], null: false
      field :section_count, Integer, null: false
      field :section_schema, GraphQL::Types::JSON, null: true
      field :sections, [ SectionType ], null: true
    end

    class HomeLayoutPayloadType < BaseObject
      field :layout, HomeLayoutType, null: true
      field :errors, [ String ], null: false
    end

    class LandingPagePayloadType < BaseObject
      field :page, LandingPageType, null: true
      field :errors, [ String ], null: false
    end

    class SectionPayloadType < BaseObject
      field :section, SectionType, null: true
      field :errors, [ String ], null: false
    end
  end
end
