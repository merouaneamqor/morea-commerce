# frozen_string_literal: true

raise "Merchandising smoke requires the isolated test environment" unless Rails.env.test?

ActiveRecord::Base.transaction do
  store = Store.create!(slug: "merch-#{SecureRandom.hex(4)}", name: "Atelier CI", currency: "MAD", whatsapp: "+212612345678")
  product = store.products.create!(name: "Studio set", slug: "studio-set", status: "active", price_cents: 10000, currency: "MAD",
    track_inventory: true, stock: 10, story: "A studio silhouette.", material: "Cotton", origin: "Morocco")
  product.product_variants.create!(option1_value: "S", option2_value: "Black", stock: 0)
  available = product.product_variants.create!(option1_value: "M", option2_value: "Black", stock: 2, price_cents: 12000)
  store.pages.create!(slug: "shipping", title: "Shipping policy", body: "Shipping terms", published: true)
  returns = store.pages.create!(slug: "returns", title: "Return policy", body: "Return terms", published: false)
  http = ActionDispatch::Integration::Session.new(Rails.application)
  http.host! "#{store.slug}.lvh.me"

  %w[fr en ar].each do |locale|
    [ "/#{locale}", "/#{locale}/products/#{product.slug}" ].each do |path|
      http.get path
      raise "Render failed: #{path} (#{http.response.status})" unless http.response.status == 200
      doc = Nokogiri::HTML(http.response.body)
      raise "Missing translation" if doc.at_css(".translation_missing")
      raise "Draft returns linked" if doc.at_css("a[href='/#{locale}/pages/returns']")
      raise "Published shipping absent" unless doc.at_css("a[href='/#{locale}/pages/shipping']")
      next unless path.include?("/products/")

      raise "First available variant not selected" unless doc.at_css("input[name='product_variant_id']")["value"] == available.id.to_s
      prices = doc.css("[data-variant-picker-target='price']").map(&:text)
      raise "Variant prices inconsistent" unless prices.size == 2 && prices.all? { |price| price == "120 MAD" }
      raise "Story not visible" unless doc.at_css("details[open]")&.text&.include?("A studio silhouette.")
      raise "Origin not shown" unless doc.at_css("#product-details").text.include?("Morocco")
      root = doc.at_css("[data-controller~='variant-picker']")
      raise "Gallery and selection do not share their event scope" unless root["data-controller"].split.include?("variant-gallery")
    end
  end

  returns.update!(published: true)
  http.get "/en"
  raise "Published returns absent" unless Nokogiri::HTML(http.response.body).at_css("a[href='/en/pages/returns']")
  store.update!(whatsapp: nil)
  http.get "/en/products/#{product.slug}"
  raise "Advice shown without a contact channel" if Nokogiri::HTML(http.response.body).at_css(".pdp-advice")
  product.product_variants.update_all(stock: 0)
  raise "Parent stock hides exhausted variants" if product.reload.available?
  http.get "/en/products/#{product.slug}"
  buttons = Nokogiri::HTML(http.response.body).css("[data-variant-picker-target='purchaseButton']")
  raise "Sold-out purchase button enabled" unless buttons.size == 4 && buttons.all? { |button| button.key?("disabled") }
  product.update!(track_inventory: false)
  raise "Untracked inventory unavailable" unless product.available?
  product.product_variants.destroy_all
  product.update!(track_inventory: true, stock: 0)
  raise "Simple product with no stock available" if product.reload.available?
  http.get "/en/products/#{product.slug}"
  raise "Simple product render failed" unless http.response.status == 200
  puts "Merchandising: FR/EN/AR, policy publication, optional advice, variant prices, story, origin and sold-out states passed"
  raise ActiveRecord::Rollback
end
