# frozen_string_literal: true

module Connections
  # Writes the catalog of one connected store into the workspace's products. Safe to run again and again: a product is
  # found by its id at the source, so a second run updates and never duplicates.
  #
  # What the source owns, and is overwritten each run: name, status, price, compare-at price, SKU, stock, stock tracking,
  # picture, and the variants with their price and stock. What the merchant owns, and is never touched: the cost of the
  # goods (profit and accounting read it), position, featured, descriptions, SEO, collections.
  # A product that disappears at the source is archived here (orders may refer to it), a variant that disappears is
  # deactivated. Nothing is removed, and nothing is archived unless the whole catalog was read.
  class ProductImport
    Result = Data.define(:created, :updated, :archived, :total)

    def initialize(connection:, transport: nil)
      @connection = connection
      @transport = transport
    end

    def call
      raise ProductSources::Error.new("disconnected") unless @connection.active?

      @connection.update!(products_sync_state: "running", products_sync_error: nil)
      seen = []
      created = updated = 0
      ProductSources.for(@connection, transport: @transport).each_item do |item|
        seen << item.external_id
        upsert(item) ? created += 1 : updated += 1
      end
      archived = archive_missing(seen)
      result = Result.new(created: created, updated: updated, archived: archived, total: seen.size)
      @connection.update!(products_sync_state: "ok", products_synced_at: Time.current, products_sync_error: nil, products_sync_counts: result.to_h.stringify_keys)
      result
    rescue ProductSources::Error => error
      @connection.update!(products_sync_state: "failed", products_sync_error: error.code)
      raise
    end

    private

    def store = @connection.store

    # true when the product was created, false when it was updated
    def upsert(item)
      product = @connection.products.find_by(external_id: item.external_id) || Product.new(store: store, store_connection: @connection, external_id: item.external_id)
      created = product.new_record?
      Product.transaction do
        stock = item.variants.any? ? item.variants.sum { |variant| variant.stock.to_i } : item.stock.to_i
        product.assign_attributes(
          name: item.name, status: item.status, price_cents: item.price_cents || 0, compare_at_cents: item.compare_at_cents, currency: store.currency,
          sku: item.sku, image_url: item.image_url, track_inventory: item.track_inventory, stock: stock, external_synced_at: Time.current
        )
        product.slug = unique_slug(item) if created
        product.save!
        sync_variants(product, item.variants)
      end
      created
    end

    def sync_variants(product, variants)
      kept = []
      variants.each do |variant|
        record = product.product_variants.find_by(external_id: variant.external_id) || product.product_variants.new(external_id: variant.external_id)
        first, second = variant.options
        record.assign_attributes(name: variant.name, sku: variant.sku, price_cents: variant.price_cents, stock: variant.stock.to_i, active: variant.active,
                                 option1_name: first&.first.presence, option1_value: first&.last.presence, option2_name: second&.first.presence, option2_value: second&.last.presence)
        record.save!
        kept << record.id
      end
      product.product_variants.where.not(external_id: nil).where.not(id: kept).update_all(active: false, updated_at: Time.current)
    end

    def archive_missing(seen)
      @connection.products.where.not(external_id: nil).where.not(external_id: seen).where.not(status: "archived").update_all(status: "archived", updated_at: Time.current)
    end

    def unique_slug(item)
      base = item.name.parameterize.presence || "product"
      slug = base
      slug = "#{base}-#{item.external_id.to_s.gsub(/\D/, "").last(6).presence || SecureRandom.hex(3)}" if store.products.exists?(slug: slug)
      slug = "#{base}-#{SecureRandom.hex(3)}" while store.products.exists?(slug: slug)
      slug
    end
  end
end
