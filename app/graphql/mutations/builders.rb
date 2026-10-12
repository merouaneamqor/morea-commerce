# frozen_string_literal: true

module Mutations
  module Builders
    class ReorderHomeSections < BaseMutation
      argument :ids, [ ID ], required: true

      field :layout, Types::Builders::HomeLayoutType, null: true
      field :errors, [ String ], null: false

      def resolve(ids:)
        { layout: Catalog::Builders.reorder_home_sections!(store, ids: ids), errors: [] }
      rescue Catalog::Builders::Error, Catalog::StoreOps::Error => e
        { layout: nil, errors: [ e.message ] }
      end
    end

    class SetHomeLayout < BaseMutation
      argument :sections, GraphQL::Types::JSON, required: true
      argument :replace, Boolean, required: false

      field :layout, Types::Builders::HomeLayoutType, null: true
      field :errors, [ String ], null: false

      def resolve(sections:, replace: false)
        { layout: Catalog::Builders.set_home_layout!(store, sections: sections, replace: replace), errors: [] }
      rescue Catalog::Builders::Error, Catalog::StoreOps::Error => e
        { layout: nil, errors: [ e.message ] }
      end
    end

    class UpsertLandingPage < BaseMutation
      argument :slug, String, required: false
      argument :new_slug, String, required: false
      argument :published, Boolean, required: false
      argument :translations, [ Types::Storefront::PageCopyInput ], required: false

      field :page, Types::Builders::LandingPageType, null: true
      field :errors, [ String ], null: false

      def resolve(**attrs)
        { page: Catalog::Builders.upsert_landing_page!(store, attrs), errors: [] }
      rescue Catalog::Builders::Error, Catalog::StoreOps::Error => e
        { page: nil, errors: [ e.message ] }
      end
    end

    class DeleteLandingPage < BaseMutation
      argument :slug, String, required: true
      argument :confirm, Boolean, required: true

      field :deleted, Boolean, null: false
      field :errors, [ String ], null: false

      def resolve(slug:, confirm:)
        Catalog::Builders.delete_landing_page!(store, slug: slug, confirm: confirm)
        { deleted: true, errors: [] }
      rescue Catalog::Builders::Error => e
        { deleted: false, errors: [ e.message ] }
      end
    end

    class UpsertLandingSection < BaseMutation
      argument :page_slug, String, required: true
      argument :id, ID, required: false
      argument :kind, String, required: false
      argument :visible, Boolean, required: false
      argument :position, Integer, required: false
      argument :image_url, String, required: false
      argument :link, String, required: false
      argument :collection_slug, String, required: false
      argument :limit, Integer, required: false
      argument :image_position, String, required: false
      argument :translations, [ Types::Storefront::SectionCopyInput ], required: false

      field :section, Types::Builders::SectionType, null: true
      field :errors, [ String ], null: false

      def resolve(page_slug:, **attrs)
        { section: Catalog::Builders.upsert_landing_section!(store, page_slug: page_slug, attrs: attrs), errors: [] }
      rescue Catalog::Builders::Error, Catalog::StoreOps::Error => e
        { section: nil, errors: [ e.message ] }
      end
    end

    class DeleteLandingSection < BaseMutation
      argument :page_slug, String, required: true
      argument :id, ID, required: true
      argument :confirm, Boolean, required: true

      field :deleted, Boolean, null: false
      field :errors, [ String ], null: false

      def resolve(page_slug:, id:, confirm:)
        Catalog::Builders.delete_landing_section!(store, page_slug: page_slug, id: id, confirm: confirm)
        { deleted: true, errors: [] }
      rescue Catalog::Builders::Error => e
        { deleted: false, errors: [ e.message ] }
      end
    end

    class ReorderLandingSections < BaseMutation
      argument :page_slug, String, required: true
      argument :ids, [ ID ], required: true

      field :page, Types::Builders::LandingPageType, null: true
      field :errors, [ String ], null: false

      def resolve(page_slug:, ids:)
        { page: Catalog::Builders.reorder_landing_sections!(store, page_slug: page_slug, ids: ids), errors: [] }
      rescue Catalog::Builders::Error => e
        { page: nil, errors: [ e.message ] }
      end
    end

    class SetLandingLayout < BaseMutation
      argument :page_slug, String, required: true
      argument :sections, GraphQL::Types::JSON, required: true
      argument :replace, Boolean, required: false

      field :page, Types::Builders::LandingPageType, null: true
      field :errors, [ String ], null: false

      def resolve(page_slug:, sections:, replace: false)
        { page: Catalog::Builders.set_landing_layout!(store, page_slug: page_slug, sections: sections, replace: replace), errors: [] }
      rescue Catalog::Builders::Error, Catalog::StoreOps::Error => e
        { page: nil, errors: [ e.message ] }
      end
    end
  end
end
