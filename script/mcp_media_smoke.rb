# frozen_string_literal: true

raise "Media smoke requires the isolated test environment" unless Rails.env.test?
ActiveJob::Base.queue_adapter = :test
suffix = SecureRandom.hex(4)
store = Store.create!(slug: "media-#{suffix}", name: "Media CI", currency: "MAD")
other = Store.create!(slug: "other-media-#{suffix}", name: "Other media CI", currency: "MAD")
product = store.products.create!(slug: "media-product", name: "Media Product", price_cents: 1000, stock: 1, status: "draft")
foreign = other.products.create!(slug: "foreign-media", name: "Foreign Media", price_cents: 1000, stock: 1, status: "draft")
png = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aN9sAAAAASUVORK5CYII=")
product.images.attach(io: StringIO.new(png), filename: "sample.png", content_type: "image/png")
attachment = product.images_attachments.first
checks = 0
assert = lambda { |message, condition| raise message unless condition; checks += 1 }
reject = lambda do |message, &block|
  rejected = false
  begin
    block.call
  rescue Catalog::MediaLibrary::Error
    rejected = true
  end
  assert.call(message, rejected)
end
edit = lambda do |operation, ids = [ attachment.id.to_s ], confirm = true|
  Catalog::MediaLibrary.edit!(store, attachment_ids: ids, edit: operation, confirm: confirm)
end
listed = Catalog::MediaLibrary.list(store, per_page: 1)
assert.call("library includes attachment", listed["total"] == 1 && listed["images"].first["id"] == attachment.id.to_s)
assert.call("library associates product", listed["images"].first["productSlug"] == product.slug)
assert.call("disk URL is absolute", listed["images"].first["url"].start_with?("http"))
assert.call("disk source not transformable", !listed["images"].first["editable"])
assert.call("pagination ends", !listed["hasMore"])
reject.call("confirmation required") { edit.call("portrait", [ attachment.id.to_s ], false) }
reject.call("disk edit rejected") { edit.call("portrait") }
reject.call("foreign attachment rejected") { Catalog::MediaLibrary.edit!(other, attachment_ids: [ attachment.id.to_s ], edit: "portrait", confirm: true) }
reject.call("foreign product filter rejected") { Catalog::MediaLibrary.list(other, product_slug: product.slug) }
reject.call("unknown edit rejected") { edit.call("random") }
reject.call("invalid batch rejected") { edit.call("square", []) }
reject.call("unknown ID rejects whole batch") { edit.call("square", [ attachment.id.to_s, "999999999" ]) }
assert.call("rejections preserve edits", MediaUrl.edits(attachment.blob.reload).empty?)
# Metadata-only Cloudinary fixtures: never call a live image processing endpoint.
attachment.blob.update!(service_name: "cloudinary")
edit.call("portrait")
assert.call("portrait metadata applied", MediaUrl.edits(attachment.blob.reload) == [ "portrait" ])
edit.call("watermark")
edit.call("square")
assert.call("new crop replaces old and preserves watermark", MediaUrl.edits(attachment.blob.reload).sort == %w[square watermark])
result = edit.call("remove_bg")
assert.call("background removal marked pending", result["processing"])
assert.call("warmup queued", ActiveJob::Base.queue_adapter.enqueued_jobs.any? { |job| job[:job] == MediaWarmupJob })
response = CatalogTools::MediaLibrary::EditProductImages.call(server_context: { store: store }, attachmentIds: [ attachment.id.to_s ], edit: "clear", confirm: true)
assert.call("MCP GraphQL edit wrapper succeeds", !response.error?)
assert.call("clear removes stored edits", MediaUrl.edits(attachment.blob.reload).empty?)
foreign.images.attach(attachment.blob)
reject.call("shared foreign source rejected") { edit.call("watermark") }
assert.call("cross-store source remains unchanged", MediaUrl.edits(attachment.blob.reload).empty?)
assert.call("media tools registered", CatalogServer::TOOLS.include?(CatalogTools::MediaLibrary::EditProductImages))
puts "Media library: #{checks} checks passed"
