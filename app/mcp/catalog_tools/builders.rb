# frozen_string_literal: true

module CatalogTools
  module Builders
    SECTION = <<~GQL.squish
      id kind label position visible imageUrl imageSrc link collectionSlug limit imagePosition
      translations { locale heading subheading body buttonLabel }
    GQL

    HOME_LAYOUT = <<~GQL.squish
      surface usingDefaults previewUrls { locale url } announcement sectionSchema
      sections { #{SECTION} }
    GQL

    LANDING = <<~GQL.squish
      slug template published previewUrls { locale url }
      translations { locale title body seoTitle seoDescription }
      sectionCount sectionSchema
      sections { #{SECTION} }
    GQL

    class GetSectionSchema < MCP::Tool
      description "Section kinds and fields for the home page builder and landing page builder (hero, ticker, featured_collection, collection_list, image_with_text, rich_text)."

      def self.call(server_context:)
        CatalogExecutor.call(
          store: server_context.fetch(:store),
          query: "query { sectionSchema }",
          include_covers: false
        )
      end
    end

    class GetHomeLayout < MCP::Tool
      description "Full home page builder layout: ordered sections, kind schema, preview URLs, and whether the store is still on unsaved theme defaults."

      def self.call(server_context:)
        CatalogExecutor.call(
          store: server_context.fetch(:store),
          query: "query { homeLayout { #{HOME_LAYOUT} } }",
          include_covers: false
        )
      end
    end

    class ReorderHomeSections < MCP::Tool
      description "Reorder home page sections by id list. First id becomes position 0."
      input_schema(
        properties: { ids: { type: "array", items: { type: "string" } } },
        required: [ "ids" ]
      )

      def self.call(ids:, server_context:)
        CatalogExecutor.call(
          store: server_context.fetch(:store),
          include_covers: false,
          query: <<~GQL,
            mutation($ids: [ID!]!) {
              reorderHomeSections(ids: $ids) { layout { #{HOME_LAYOUT} } errors }
            }
          GQL
          variables: { ids: ids }
        )
      end
    end

    class SetHomeLayout < MCP::Tool
      description "Build or rewrite the home page from an ordered sections array. Each item: kind (required when new), optional id, visible, imageUrl, link, collectionSlug, limit, imagePosition, translations. replace: true deletes sections omitted from the list."
      input_schema(
        properties: {
          sections: { type: "array", items: { type: "object" } },
          replace: { type: "boolean" }
        },
        required: [ "sections" ]
      )

      def self.call(sections:, server_context:, replace: false)
        CatalogExecutor.call(
          store: server_context.fetch(:store),
          include_covers: false,
          query: <<~GQL,
            mutation($sections: JSON!, $replace: Boolean) {
              setHomeLayout(sections: $sections, replace: $replace) { layout { #{HOME_LAYOUT} } errors }
            }
          GQL
          variables: { sections: sections, replace: replace }
        )
      end
    end

    class ListLandingPages < MCP::Tool
      description "List landing pages (template=landing). Content pages like about/shipping are not included."

      def self.call(server_context:)
        CatalogExecutor.call(
          store: server_context.fetch(:store),
          include_covers: false,
          query: <<~GQL
            query {
              landingPages {
                slug template published sectionCount
                previewUrls { locale url }
                translations { locale title seoTitle }
              }
            }
          GQL
        )
      end
    end

    class GetLandingPage < MCP::Tool
      description "Get one landing page with its builder sections and preview URLs."
      input_schema(
        properties: { slug: { type: "string" } },
        required: [ "slug" ]
      )

      def self.call(slug:, server_context:)
        CatalogExecutor.call(
          store: server_context.fetch(:store),
          include_covers: false,
          query: <<~GQL,
            query($slug: String!) { landingPage(slug: $slug) { #{LANDING} } }
          GQL
          variables: { slug: slug }
        )
      end
    end

    class UpsertLandingPage < MCP::Tool
      description "Create or update a landing page. Pass slug to update. A new page needs a fr title. Sets template to landing. Public URL is /:locale/pages/:slug."
      input_schema(
        properties: {
          slug: { type: "string" },
          newSlug: { type: "string" },
          published: { type: "boolean" },
          translations: { type: "array", items: { type: "object" }, description: "locale, title, body, seoTitle, seoDescription" }
        }
      )

      def self.call(server_context:, **attrs)
        CatalogExecutor.call(
          store: server_context.fetch(:store),
          include_covers: false,
          query: <<~GQL,
            mutation($slug: String, $newSlug: String, $published: Boolean, $translations: [StorefrontPageCopyInput!]) {
              upsertLandingPage(slug: $slug, newSlug: $newSlug, published: $published, translations: $translations) {
                page { #{LANDING} }
                errors
              }
            }
          GQL
          variables: attrs.compact
        )
      end
    end

    class DeleteLandingPage < MCP::Tool
      description "Delete a landing page and its sections. Requires confirm: true."
      input_schema(
        properties: { slug: { type: "string" }, confirm: { type: "boolean" } },
        required: %w[slug confirm]
      )

      def self.call(slug:, confirm:, server_context:)
        CatalogExecutor.call(
          store: server_context.fetch(:store),
          include_covers: false,
          query: <<~GQL,
            mutation($slug: String!, $confirm: Boolean!) {
              deleteLandingPage(slug: $slug, confirm: $confirm) { deleted errors }
            }
          GQL
          variables: { slug: slug, confirm: confirm }
        )
      end
    end

    class UpsertLandingSection < MCP::Tool
      description "Add a new landing-page section (omit id, pass kind) or edit an existing one (pass id from get_landing_page). Same kinds/fields as the home page builder."
      input_schema(
        properties: {
          pageSlug: { type: "string" },
          id: { type: "string", description: "Existing section id to edit. Omit to add a new section." },
          kind: { type: "string", enum: %w[hero ticker featured_collection collection_list image_with_text rich_text], description: "Required when adding a new section." },
          visible: { type: "boolean" },
          position: { type: "integer" },
          imageUrl: { type: "string" },
          link: { type: "string" },
          collectionSlug: { type: "string" },
          limit: { type: "integer" },
          imagePosition: { type: "string", enum: %w[left right] },
          translations: { type: "array", items: { type: "object" }, description: "locale plus heading, subheading, body, buttonLabel" }
        },
        required: [ "pageSlug" ]
      )

      def self.call(pageSlug:, server_context:, **attrs)
        CatalogExecutor.call(
          store: server_context.fetch(:store),
          include_covers: false,
          query: <<~GQL,
            mutation(
              $pageSlug: String!, $id: ID, $kind: String, $visible: Boolean, $position: Int, $imageUrl: String,
              $link: String, $collectionSlug: String, $limit: Int, $imagePosition: String, $translations: [StorefrontSectionCopyInput!]
            ) {
              upsertLandingSection(
                pageSlug: $pageSlug, id: $id, kind: $kind, visible: $visible, position: $position, imageUrl: $imageUrl,
                link: $link, collectionSlug: $collectionSlug, limit: $limit, imagePosition: $imagePosition, translations: $translations
              ) { section { #{SECTION} } errors }
            }
          GQL
          variables: { pageSlug: pageSlug }.merge(attrs.compact)
        )
      end
    end

    class DeleteLandingSection < MCP::Tool
      description "Remove a section from a landing page. Requires confirm: true."
      input_schema(
        properties: {
          pageSlug: { type: "string" },
          id: { type: "string" },
          confirm: { type: "boolean" }
        },
        required: %w[pageSlug id confirm]
      )

      def self.call(pageSlug:, id:, confirm:, server_context:)
        CatalogExecutor.call(
          store: server_context.fetch(:store),
          include_covers: false,
          query: <<~GQL,
            mutation($pageSlug: String!, $id: ID!, $confirm: Boolean!) {
              deleteLandingSection(pageSlug: $pageSlug, id: $id, confirm: $confirm) { deleted errors }
            }
          GQL
          variables: { pageSlug: pageSlug, id: id, confirm: confirm }
        )
      end
    end

    class ReorderLandingSections < MCP::Tool
      description "Reorder sections on a landing page. First id becomes position 0."
      input_schema(
        properties: {
          pageSlug: { type: "string" },
          ids: { type: "array", items: { type: "string" } }
        },
        required: %w[pageSlug ids]
      )

      def self.call(pageSlug:, ids:, server_context:)
        CatalogExecutor.call(
          store: server_context.fetch(:store),
          include_covers: false,
          query: <<~GQL,
            mutation($pageSlug: String!, $ids: [ID!]!) {
              reorderLandingSections(pageSlug: $pageSlug, ids: $ids) { page { #{LANDING} } errors }
            }
          GQL
          variables: { pageSlug: pageSlug, ids: ids }
        )
      end
    end

    class SetLandingLayout < MCP::Tool
      description "Set the full ordered section list for a landing page. replace: true removes sections omitted from the list."
      input_schema(
        properties: {
          pageSlug: { type: "string" },
          sections: { type: "array", items: { type: "object" } },
          replace: { type: "boolean" }
        },
        required: %w[pageSlug sections]
      )

      def self.call(pageSlug:, sections:, server_context:, replace: false)
        CatalogExecutor.call(
          store: server_context.fetch(:store),
          include_covers: false,
          query: <<~GQL,
            mutation($pageSlug: String!, $sections: JSON!, $replace: Boolean) {
              setLandingLayout(pageSlug: $pageSlug, sections: $sections, replace: $replace) {
                page { #{LANDING} }
                errors
              }
            }
          GQL
          variables: { pageSlug: pageSlug, sections: sections, replace: replace }
        )
      end
    end
  end
end
