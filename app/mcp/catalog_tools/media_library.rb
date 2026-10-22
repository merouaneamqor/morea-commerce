# frozen_string_literal: true

module CatalogTools
  module MediaLibrary
    class ListMedia < MCP::Tool
      description "Paginated product media library. Each image includes attachment ID, product slug, filename, gallery position, URL, existing edits, storage and whether transformations are supported. Optional productSlug filter. Lists URLs, not inline previews; use get_product to view photos."
      input_schema(properties: { page: { type: "integer", minimum: 1 }, perPage: { type: "integer", minimum: 1, maximum: 100 }, productSlug: { type: "string" } })

      def self.call(server_context:, page: 1, perPage: 30, productSlug: nil)
        CatalogExecutor.call(
          store: server_context.fetch(:store), include_covers: false,
          query: "query($page: Int!, $perPage: Int!, $productSlug: String) { mediaLibrary(page: $page, perPage: $perPage, productSlug: $productSlug) }",
          variables: { page: page, perPage: perPage, productSlug: productSlug }.compact
        )
      end
    end

    class EditProductImages < MCP::Tool
      description "Apply existing app media transformations to 1-100 product attachment IDs: portrait (3:4 crop), square, watermark, remove_bg, or clear. Cloudinary images only. Unknown or cross-store IDs reject the whole batch. Existing edits compose; a new crop replaces the previous crop. clear removes all stored edits. Originals remain intact. Background removal is asynchronous and may use the store's Cloudinary quota. Requires confirm: true. Re-read get_product/list_media to inspect updated delivery URLs."
      input_schema(properties: {
        attachmentIds: { type: "array", minItems: 1, maxItems: 100, items: { type: "string" } },
        edit: { type: "string", enum: %w[portrait square watermark remove_bg clear] }, confirm: { type: "boolean" }
      }, required: %w[attachmentIds edit confirm])

      def self.call(attachmentIds:, edit:, confirm:, server_context:)
        CatalogExecutor.call(
          store: server_context.fetch(:store), include_covers: false,
          query: <<~GQL,
            mutation($attachmentIds: [ID!]!, $edit: String!, $confirm: Boolean!) {
              editProductImages(attachmentIds: $attachmentIds, edit: $edit, confirm: $confirm) { result errors }
            }
          GQL
          variables: { attachmentIds: attachmentIds, edit: edit, confirm: confirm }
        )
      end
    end
  end
end
