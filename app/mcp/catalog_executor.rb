# frozen_string_literal: true

class CatalogExecutor
  PRODUCT_FIELDS = <<~GQL.squish
    id slug status priceDh compareAtDh currency sku stock trackInventory featured position collectionSlugs
    coverUrl
    variants { id size color colorHex sku stock active priceDh }
    images { id filename url position }
    translations { locale name shortDescription story material fit movement dimensions origin care seoTitle seoDescription }
  GQL

  STATS_FIELDS = <<~GQL.squish
    from to placedCount placedRevenueDh shippingDh discountDh averageOrderDh
    deliveredCount deliveredRevenueDh deliveryRate cancelRate returnRate
    byStatus { status count }
    pipeline { status count }
    byCity { city orders delivered deliveryRate revenueDh }
    byDay { date placed delivered revenueDh }
  GQL

  PRODUCT_STAT_FIELDS = <<~GQL.squish
    slug name status priceDh stock stockValueDh lowStock
    unitsPlaced unitsDelivered unitsCancelled unitsReturned
    revenuePlacedDh revenueDeliveredDh orders
    variants { name unitsPlaced unitsDelivered stock }
  GQL

  ORDER_FIELDS = <<~GQL.squish
    number status createdAt confirmedAt shippedAt deliveredAt cancelledAt returnedAt
    city district subtotalDh shippingDh discountDh totalDh discountCode notes
    sendit { code status feeDh deliverBy error }
    items { productSlug productName variantName quantity unitPriceDh totalDh }
  GQL

  COLLECTION_FIELDS = <<~GQL.squish
    id slug published position productSlugs
    coverUrl
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
    MCP::Tool::Response.new(response_content(payload, errored), error: errored)
  end

  def self.response_content(payload, errored)
    parts = [ { type: "text", text: JSON.generate(payload) } ]
    return parts if errored

    cover_entries(payload).each do |entry|
      bytes = Catalog::Images.jpeg_bytes(entry[:url])
      next unless bytes

      parts << { type: "text", text: "Cover photo for #{entry[:kind]} #{entry[:slug]}. This is the storefront image." }
      parts << { type: "image", data: Base64.strict_encode64(bytes), mimeType: "image/jpeg" }
    end
    parts
  end

  def self.cover_entries(payload)
    data = payload["data"]
    return [] unless data.is_a?(Hash)

    entries = []
    collect = lambda do |kind, record|
      return unless record.is_a?(Hash)

      entries << { kind: kind, slug: record["slug"], url: record["coverUrl"] }
    end

    Array(data["products"]).each { |record| collect.call("product", record) }
    collect.call("product", data["product"])
    Array(data["collections"]).each { |record| collect.call("collection", record) }
    collect.call("collection", data["collection"])
    data.each_value do |value|
      next unless value.is_a?(Hash)

      collect.call("product", value["product"])
      collect.call("collection", value["collection"])
    end

    entries.select { |entry| entry[:slug].present? && entry[:url].present? }
      .uniq { |entry| [ entry[:kind], entry[:slug] ] }
      .first(8)
  end

  def self.payload_errors?(payload)
    data = payload["data"]
    return false unless data.is_a?(Hash)

    data.values.any? { |value| value.is_a?(Hash) && Array(value["errors"]).any? }
  end
end
