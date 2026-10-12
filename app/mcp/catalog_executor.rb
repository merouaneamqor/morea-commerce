# frozen_string_literal: true

class CatalogExecutor
  PRODUCT_FIELDS = <<~GQL.squish
    id slug status priceDh compareAtDh currency sku stock trackInventory featured position collectionSlugs
    images { id filename url position }
    translations { locale name shortDescription story material fit movement dimensions origin care seoTitle seoDescription }
  GQL

  COLLECTION_FIELDS = <<~GQL.squish
    id slug published position productSlugs
    image { id filename url position }
    translations { locale name subtitle description }
  GQL

  def self.call(store:, query:, variables: {})
    result = MoreaSchema.execute(
      query,
      variables: variables.deep_stringify_keys,
      context: { store: store }
    )
    payload = result.to_h
    errored = payload["errors"].present? || payload_errors?(payload)
    MCP::Tool::Response.new(
      [ { type: "text", text: JSON.generate(payload) } ],
      error: errored
    )
  end

  def self.payload_errors?(payload)
    data = payload["data"]
    return false unless data.is_a?(Hash)

    data.values.any? { |value| value.is_a?(Hash) && Array(value["errors"]).any? }
  end
end
