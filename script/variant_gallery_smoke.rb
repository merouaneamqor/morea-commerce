# frozen_string_literal: true

raise "Gallery smoke requires the isolated test environment" unless Rails.env.test?
ActiveJob::Base.queue_adapter = :test

store = Store.create!(slug: "gallery-#{SecureRandom.hex(4)}", name: "Gallery CI", currency: "MAD")
product = store.products.create!(slug: "color-photos", name: "Color photos", price_cents: 1000, status: "active")
pink = product.product_variants.create!(option1_value: "S", option2_value: "Pink", stock: 2)
pink_m = product.product_variants.create!(option1_value: "M", option2_value: "Pink", stock: 2)
black = product.product_variants.create!(option1_value: "S", option2_value: "Black", stock: 2)
plain = product.product_variants.create!(option1_value: "S", option2_value: "White", stock: 2)
legacy = product.product_variants.create!(name: "L / Pink", stock: 2)
png = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aN9sAAAAASUVORK5CYII="

begin
  # Exercise the actual MCP upload tool, rather than attaching variant fixtures directly.
  result = CatalogTools::AddVariantImages.call(slug: product.slug, variantId: pink.id.to_s,
    images: %w[pink-front.png pink-back.png].map { |name| { base64: png, filename: name, contentType: "image/png" } },
    server_context: { store: store }).to_h
  raise "MCP upload failed" if result[:isError] || result["isError"]
  raise "MCP photos not saved" unless pink.images.reload.count == 2

  http = ActionDispatch::Integration::Session.new(Rails.application)
  http.host! "#{store.slug}.lvh.me"
  http.get "/en/products/#{product.slug}"
  raise "Product page failed: #{http.response.status}" unless http.response.status == 200
  doc = Nokogiri::HTML(http.response.body)
  payload = JSON.parse(doc.at_css("[data-variant-picker-variants-value]")["data-variant-picker-variants-value"])
  photos = payload.index_by { |variant| variant["id"] }
  raise "Color gallery missing" unless photos.fetch(pink.id)["images"].size == 2
  raise "Color gallery not shared across sizes" unless photos.fetch(pink.id)["images"] == photos.fetch(pink_m.id)["images"]
  raise "Legacy size did not inherit its color photos" unless photos.fetch(legacy.id)["images"] == photos.fetch(pink.id)["images"]
  raise "Unmapped color inherited another color" unless photos.fetch(plain.id)["images"].nil?
  raise "Dynamic gallery template missing" unless doc.at_css("template[data-variant-gallery-target='shotTemplate'] img")

  # Upload a different color through the admin editor.
  password = SecureRandom.hex(16)
  user = store.users.create!(email: "gallery@example.test", password: password, admin: true)
  http.post "/admin/login", params: { email: user.email, password: password }
  raise "Admin login failed" unless http.response.redirect?
  file = Tempfile.new([ "black-front", ".png" ])
  file.binmode
  file.write(Base64.decode64(png))
  file.flush
  http.patch "/admin/products/#{product.slug}/variants/#{black.id}", params: {
    product_variant: { images: [ Rack::Test::UploadedFile.new(file.path, "image/png") ] }
  }
  raise "Admin photo upload failed" unless http.response.redirect? && black.images.reload.count == 1
  http.get "/en/products/#{product.slug}"
  payload = JSON.parse(Nokogiri::HTML(http.response.body).at_css("[data-variant-picker-variants-value]")["data-variant-picker-variants-value"])
  photos = payload.index_by { |variant| variant["id"] }
  raise "Admin color photo not exposed on storefront" unless photos.fetch(black.id)["images"]&.size == 1
  raise "Different colors share a main image" if photos.fetch(black.id)["images"].first == photos.fetch(pink.id)["images"].first
  http.get "/admin/products/#{product.slug}/variants/#{black.id}/edit"
  raise "Admin main photo guidance missing" unless http.response.status == 200 && http.response.body.include?("Main photo")
  product.images.attach(io: StringIO.new(Base64.decode64(png)), filename: "product-front.png", content_type: "image/png")
  product.images.attach(io: StringIO.new(Base64.decode64(png)), filename: "product-back.png", content_type: "image/png")
  library = product.images_attachments.order(:id).to_a
  selected = library.reverse.map { |image| image.blob_id.to_s }
  http.patch "/admin/products/#{product.slug}/variants/bulk_update", params: { variants: {
    "0" => { id: black.id, option1_value: "S", option2_value: "Black", stock: 2, active: "1", media_blob_ids: selected.to_json }
  } }
  raise "Picker selection was not saved in main-first order" unless black.reload.ordered_images.map { |image| image.blob_id.to_s } == selected
  raise "Picker duplicated image blobs" unless black.images.map(&:blob_id).sort == library.map(&:blob_id).sort
  original_ids = black.ordered_images.map(&:id).sort
  http.patch "/admin/products/#{product.slug}/variants/#{black.id}", params: { product_variant: { media_blob_ids: selected.reverse.to_json } }
  raise "Variant editor did not save image order" unless black.reload.ordered_images.map { |image| image.blob_id.to_s } == selected.reverse
  raise "Reordering changed attachment IDs" unless black.images.map(&:id).sort == original_ids
  http.get "/admin/products/#{product.slug}/edit"
  raise "Product editor failed" unless http.response.status == 200
  doc = Nokogiri::HTML(http.response.body)
  raise "Media picker missing" unless doc.at_css("dialog[data-media-picker-target='dialog']")
  raise "Variant form is nested in product form" if doc.at_css("#product-form #product-variants-form")
  raise "Variants precede product media" unless http.response.body.index('id="product-form"') < http.response.body.index('id="product-variants-form"')
  File.write(Rails.root.join("tmp/admin_media_smoke.html"), http.response.body)
  foreign_blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new(Base64.decode64(png)), filename: "other-store.png", content_type: "image/png", service_name: "test")
  http.patch "/admin/products/#{product.slug}/variants/#{black.id}", params: { product_variant: { stock: 99, media_blob_ids: [ foreign_blob.id.to_s ].to_json } }
  raise "Foreign media or partial variant changes accepted" unless black.reload.stock == 2 && black.images.map(&:id).sort == original_ids
  http.patch "/admin/products/#{product.slug}/variants/#{black.id}", params: { product_variant: { media_blob_ids: "[]" } }
  raise "Clearing variant media failed" if black.images.reload.any?
  raise "Clearing variant media removed product photos" unless product.images.reload.count == 2
  # A gallery can reuse a blob. Purging one attachment must preserve every other use.
  shared_blob = library.first.blob
  shared_blob.purge
  raise "Shared image file was deleted" unless shared_blob.service.exist?(shared_blob.key)
  puts "Variant galleries: MCP + admin uploads, same-color size sharing, legacy options, unmapped-color fallback and product without general photos OK"
  puts "Admin media picker: reuse existing photos, main-first order, stable IDs, bulk + individual saves, clear to inherit and reject foreign media atomically OK"
ensure
  file&.close!
  product&.product_variants&.each { |variant| variant.images.purge }
  product&.images&.purge
  foreign_blob&.purge
  store&.destroy!
end
