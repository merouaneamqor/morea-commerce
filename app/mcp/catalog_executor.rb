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

  def self.call(store:, query:, variables: {}, include_covers: true)
    result = MoreaSchema.execute(
      query,
      variables: variables.deep_stringify_keys,
      context: { store: store }
    )
    payload = result.to_h
    errored = payload["errors"].present? || payload_errors?(payload)
    MCP::Tool::Response.new(response_content(payload, errored, include_covers: include_covers), error: errored)
  end

  def self.response_content(payload, errored, include_covers: true)
    parts = [ { type: "text", text: JSON.generate(payload) } ]
    return parts if errored || !include_covers

    cover_entries(payload).each do |entry|
      bytes = Catalog::Images.jpeg_bytes(entry[:url])
      unless bytes
        parts << { type: "text", text: "Image preview unavailable for #{entry[:kind]} #{entry[:slug]}. Original image URL: #{entry[:url]}" }
        next
      end

      parts << { type: "text", text: "#{entry[:label] || 'Cover photo'} for #{entry[:kind]} #{entry[:slug]}. Image URL: #{entry[:url]}" }
      parts << { type: "image", data: Base64.strict_encode64(bytes), mimeType: "image/jpeg" }
    end
    if cover_entries(payload).size == 8
      parts << { type: "text", text: "At most 8 image previews are attached per response. All image URLs remain in the JSON. Use get_product for a product gallery." }
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
    if data["product"].is_a?(Hash)
      product = data["product"]
      Array(product["images"]).each do |image|
        next unless image.is_a?(Hash)
        next if image["url"] == product["coverUrl"]

        entries << { kind: "product", slug: product["slug"], url: image["url"],
                     label: "Gallery image #{image['position'].to_i + 1} (#{image['filename']})" }
      end
    end
    Array(data["collections"]).each { |record| collect.call("collection", record) }
    collect.call("collection", data["collection"])
    data.each_value do |value|
      next unless value.is_a?(Hash)

      collect.call("product", value["product"])
      collect.call("collection", value["collection"])
    end

    entries.select { |entry| entry[:slug].present? && entry[:url].present? }
      .uniq { |entry| [ entry[:kind], entry[:slug], entry[:url] ] }
      .first(8)
  end

  def self.payload_errors?(payload)
    data = payload["data"]
    return false unless data.is_a?(Hash)

    data.values.any? { |value| value.is_a?(Hash) && Array(value["errors"]).any? }
  end
end
