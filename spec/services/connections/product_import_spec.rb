require "rails_helper"

RSpec.describe Connections::ProductImport do
  let(:store) { Store.create!(slug: "imp-#{SecureRandom.hex(5)}", name: "Importer", currency: "MAD") }
  let(:other_store) { Store.create!(slug: "imp-other-#{SecureRandom.hex(4)}", name: "Other", currency: "MAD") }
  let(:secret) { "synthetic-webhook-secret" }

  Reply = Struct.new(:code, :body, :headers) do
    def [](name) = headers&.fetch(name, nil)
  end

  def woo_connection(workspace = store, domain: "shop-#{SecureRandom.hex(3)}.example.test")
    workspace.store_connections.create!(provider: "woocommerce", name: "Woo shop", external_domain: domain, webhook_secret: secret).tap do |connection|
      connection.update!(api_credentials: { consumer_key: "ck_synthetic", consumer_secret: "cs_synthetic" })
    end
  end

  def youcan_connection(workspace = store)
    workspace.store_connections.create!(provider: "youcan", name: "YouCan shop", external_domain: "yc-#{SecureRandom.hex(3)}.example.test", external_store_id: SecureRandom.uuid, webhook_secret: secret).tap do |connection|
      connection.update!(api_credentials: { access_token: "yc_synthetic_token" })
    end
  end

  # A transport that answers from a list of [url-part, reply] and remembers what it was asked.
  def transport(*answers)
    calls = []
    lambda do |uri, request|
      calls << [ uri.to_s, request ]
      match = answers.find { |part, _reply| uri.to_s.include?(part) } or raise "unexpected request #{uri}"
      match.last
    end.tap { |t| t.define_singleton_method(:calls) { calls } }
  end

  def json(value, headers = {}) = Reply.new("200", JSON.generate(value), headers)

  describe "WooCommerce" do
    let(:connection) { woo_connection }
    let(:simple) { { id: 11, name: "Basic Tee", status: "publish", type: "simple", price: "199.50", regular_price: "249.00", on_sale: true, sku: "TEE-1", manage_stock: true, stock_quantity: 7, images: [ { src: "https://cdn.example.test/tee.jpg" } ] } }
    let(:variable) { { id: 12, name: "Hoodie", status: "publish", type: "variable", price: "300", regular_price: "300", manage_stock: false, images: [] } }
    let(:variations) { [ { id: 121, sku: "H-S", price: "300", regular_price: "300", manage_stock: true, stock_quantity: 4, status: "publish", attributes: [ { name: "Size", option: "S" } ] },
                         { id: 122, sku: "H-M", price: "320.25", regular_price: "320.25", manage_stock: true, stock_quantity: 6, status: "publish", attributes: [ { name: "Size", option: "M" } ] } ] }

    def run(connection, rows: [ simple, variable ], variations: self.variations, headers: { "X-WP-TotalPages" => "1" })
      Connections::ProductImport.new(connection: connection, transport: transport([ "/products/12/variations", json(variations) ], [ "/products?", json(rows, headers) ])).call
    end

    it "imports simple and variable products with their own price and stock, in whole centimes" do
      result = run(connection)

      expect(result).to have_attributes(created: 2, updated: 0, archived: 0, total: 2)
      tee = connection.products.find_by!(external_id: "11")
      expect(tee).to have_attributes(name: "Basic Tee", status: "active", price_cents: 19_950, compare_at_cents: 24_900, sku: "TEE-1", stock: 7, track_inventory: true, store_id: store.id,
                                     image_url: "https://cdn.example.test/tee.jpg", currency: "MAD")
      hoodie = connection.products.find_by!(external_id: "12")
      expect(hoodie.price_cents).to eq(30_000)                                # the lowest variation price
      expect(hoodie.product_variants.order(:external_id).map { |v| [ v.name, v.price_cents, v.stock, v.option1_name, v.option1_value ] }).to eq(
        [ [ "S", 30_000, 4, "Size", "S" ], [ "M", 32_025, 6, "Size", "M" ] ]
      )
      expect(hoodie.stock).to eq(10)                                          # 4 + 6
      expect(connection.reload).to have_attributes(products_sync_state: "ok", products_sync_counts: { "created" => 2, "updated" => 0, "archived" => 0, "total" => 2 })
      expect(connection.products_synced_at).to be_within(5.seconds).of(Time.current)
    end

    it "asks with the store's keys and reads every page" do
      t = transport([ "/products/12/variations", json(variations) ], [ "page=2", json([ variable ], { "X-WP-TotalPages" => "2" }) ], [ "page=1", json([ simple ], { "X-WP-TotalPages" => "2" }) ])
      result = described_class.new(connection: connection, transport: t).call

      expect(result.total).to eq(2)
      first_uri, first_request = t.calls.first
      expect(first_uri).to include("https://#{connection.external_domain}/wp-json/wc/v3/products?", "per_page=100")
      expect(first_request["Authorization"]).to eq("Basic " + Base64.strict_encode64("ck_synthetic:cs_synthetic"))
    end

    it "runs again without duplicating: updates, keeps what the merchant owns, deactivates a variation that went" do
      run(connection)
      tee = connection.products.find_by!(external_id: "11")
      tee.update!(cost_cents: 5_000, featured: true, position: 3)

      result = run(connection, rows: [ simple.merge(price: "210", stock_quantity: 3), variable ], variations: [ variations.first ])

      expect(result).to have_attributes(created: 0, updated: 2, archived: 0)
      expect(connection.products.count).to eq(2)
      expect(tee.reload).to have_attributes(price_cents: 21_000, stock: 3, cost_cents: 5_000, featured: true, position: 3)   # price and stock follow the store, cost stays
      hoodie = connection.products.find_by!(external_id: "12")
      expect(hoodie.product_variants.find_by!(external_id: "122").active).to be(false)   # not deleted: orders may refer to it
      expect(hoodie.product_variants.find_by!(external_id: "121").active).to be(true)
    end

    it "archives a product that left the store, only after the whole catalog was read" do
      run(connection)

      result = run(connection, rows: [ simple ])

      expect(result.archived).to eq(1)
      expect(connection.products.find_by!(external_id: "12").status).to eq("archived")
      expect(connection.products.find_by!(external_id: "11").status).to eq("active")
    end

    it "keeps the catalog and records the failure when the store refuses the keys" do
      run(connection)

      expect { described_class.new(connection: connection, transport: transport([ "/products", Reply.new("401", "{}", {}) ])).call }.to raise_error(Connections::ProductSources::Error) { |e| expect(e.code).to eq("invalid_credentials") }

      expect(connection.reload).to have_attributes(products_sync_state: "failed", products_sync_error: "invalid_credentials")
      expect(connection.products.where(status: "archived").count).to eq(0)   # a failed read never archives
      expect(connection.products.count).to eq(2)
    end

    it "does nothing without keys, for a switched-off store, or for an address that is not a public host name" do
      connection.update!(api_credentials: {})
      expect { described_class.new(connection: connection).call }.to raise_error(Connections::ProductSources::Error) { |e| expect(e.code).to eq("credentials_missing") }

      keyed = woo_connection
      keyed.update!(active: false)
      expect { described_class.new(connection: keyed).call }.to raise_error(Connections::ProductSources::Error) { |e| expect(e.code).to eq("disconnected") }

      %w[localhost 127.0.0.1 10.0.0.5 intranet.local shop.internal singlelabel].each do |host|
        record = woo_connection(domain: "x#{SecureRandom.hex(3)}.example.test")
        StoreConnection.where(id: record.id).update_all(external_domain: host)   # the address is read-only on a record
        expect { described_class.new(connection: record.reload, transport: ->(*) { raise "must not be fetched" }).call }.to raise_error(Connections::ProductSources::Error) { |e| expect(e.code).to eq("unsafe_domain"), host }
      end
    end

    it "keeps two workspaces apart even when the products share an id at their stores" do
      other = woo_connection(other_store)
      run(connection)
      run(other)

      expect(Product.where(external_id: "11").pluck(:store_id)).to contain_exactly(store.id, other_store.id)
      expect(store.products.imported.count).to eq(2)
      expect(other_store.products.imported.count).to eq(2)
    end

    it "gives every imported product its own slug, even for the same name" do
      run(connection, rows: [ simple, simple.merge(id: 13) ])

      expect(connection.products.pluck(:slug).uniq.size).to eq(2)
    end
  end

  describe "YouCan" do
    let(:connection) { youcan_connection }
    let(:page) do
      { data: [ { id: "yc-1", name: "Cap", price: "89", compare_at_price: "120", sku: "CAP", inventory: 12, is_active: true, images: [ { url: "https://cdn.example.test/cap.png" } ], variants: [] },
                { id: "yc-2", name: "Sneakers", price: "499.99", is_active: false, variants: [ { id: "v1", price: "499.99", sku: "SN-40", inventory: 3, variations: { "Size" => "40" } },
                                                                                             { id: "v2", price: "519.00", sku: "SN-41", inventory: 0, variations: [ { name: "Size", value: "41" } ] } ] } ],
        meta: { pagination: { total_pages: 1 } } }
    end

    it "imports a product and a product with variants, sending the access token" do
      t = transport([ "api.youcan.shop/products", json(page) ])
      result = described_class.new(connection: connection, transport: t).call

      expect(result).to have_attributes(created: 2, total: 2)
      expect(t.calls.first.last["Authorization"]).to eq("Bearer yc_synthetic_token")
      cap = connection.products.find_by!(external_id: "yc-1")
      expect(cap).to have_attributes(name: "Cap", price_cents: 8_900, compare_at_cents: 12_000, stock: 12, status: "active", sku: "CAP", image_url: "https://cdn.example.test/cap.png")
      sneakers = connection.products.find_by!(external_id: "yc-2")
      expect(sneakers).to have_attributes(status: "draft", price_cents: 49_999, stock: 3)
      expect(sneakers.product_variants.order(:external_id).map { |v| [ v.name, v.price_cents, v.stock ] }).to eq([ [ "40", 49_999, 3 ], [ "41", 51_900, 0 ] ])
    end

    it "refuses an answer it cannot read rather than importing a wrong product" do
      expect { described_class.new(connection: connection, transport: transport([ "api.youcan.shop", json({ oops: true }) ])).call }.to raise_error(Connections::ProductSources::Error) { |e| expect(e.code).to eq("invalid_response") }
      expect(connection.products.count).to eq(0)
      expect { described_class.new(connection: connection, transport: transport([ "api.youcan.shop", Reply.new("200", "not json", {}) ])).call }.to raise_error(Connections::ProductSources::Error)
    end
  end

  describe "Shopify" do
    let(:connection) do
      store.store_connections.create!(provider: "shopify", name: "Shopify shop", external_domain: "imp-#{SecureRandom.hex(3)}.myshopify.com", shopify_oauth: true, shopify_app: "seallo_connect",
                                      webhook_secret: secret, shopify_api_verified_at: Time.current)
    end
    def gql_variant(id, title, sku, price, compare, stock, options)
      { "id" => "gid://shopify/ProductVariant/#{id}", "title" => title, "sku" => sku, "price" => price, "compareAtPrice" => compare, "inventoryQuantity" => stock,
        "selectedOptions" => options.map { |name, value| { "name" => name, "value" => value } } }
    end

    def gql_product(id, title, status, tracks, total, image, variants)
      { "id" => "gid://shopify/Product/#{id}", "title" => title, "status" => status, "tracksInventory" => tracks, "totalInventory" => total,
        "featuredImage" => image && { "url" => image }, "variants" => { "nodes" => variants } }
    end

    def gql_page(nodes, next_cursor)
      { "products" => { "pageInfo" => { "hasNextPage" => !next_cursor.nil?, "endCursor" => next_cursor }, "nodes" => nodes } }
    end

    let(:page_one) do
      gql_page([ gql_product(1, "Tracksuit", "ACTIVE", true, 9, "https://cdn.shopify.test/t.jpg", [
        gql_variant(10, "M / Black", "TR-M-B", "389.00", "450.00", 5, [ [ "Size", "M" ], [ "Color", "Black" ] ]),
        gql_variant(11, "L / Black", "TR-L-B", "399.00", nil, 4, [ [ "Size", "L" ], [ "Color", "Black" ] ])
      ]) ], "c1")
    end
    let(:page_two) do
      gql_page([ gql_product(2, "Plain Cap", "DRAFT", false, 0, nil, [ gql_variant(20, "Default Title", "CAP", "79.90", nil, 0, [ [ "Title", "Default Title" ] ]) ]) ], nil)
    end


    it "reads every page through the shop's API: variants keep their own price and stock, a product with no option is one line" do
      calls = []
      api = instance_double(Connections::ShopifyApi)
      allow(api).to receive(:graphql) { |query:, variables:| calls << variables[:cursor]; variables[:cursor].nil? ? page_one : page_two }
      allow(Connections::ShopifyApi).to receive(:new).and_return(api)

      result = described_class.new(connection: connection).call

      expect(calls).to eq([ nil, "c1" ])
      expect(result).to have_attributes(created: 2, total: 2)
      tracksuit = connection.products.find_by!(external_id: "gid://shopify/Product/1")
      expect(tracksuit).to have_attributes(name: "Tracksuit", status: "active", price_cents: 38_900, compare_at_cents: 45_000, stock: 9, track_inventory: true, image_url: "https://cdn.shopify.test/t.jpg")
      expect(tracksuit.product_variants.order(:external_id).map { |v| [ v.name, v.price_cents, v.stock, v.sku ] }).to eq([ [ "M / Black", 38_900, 5, "TR-M-B" ], [ "L / Black", 39_900, 4, "TR-L-B" ] ])
      cap = connection.products.find_by!(external_id: "gid://shopify/Product/2")
      expect(cap).to have_attributes(status: "draft", price_cents: 7_990, sku: "CAP", track_inventory: false)
      expect(cap.product_variants.count).to eq(0)
    end

    it "turns a Shopify permission error into a recorded failure" do
      api = instance_double(Connections::ShopifyApi)
      allow(api).to receive(:graphql).and_raise(Connections::ShopifyApi::Error.new("missing_scopes"))
      allow(Connections::ShopifyApi).to receive(:new).and_return(api)

      expect { described_class.new(connection: connection).call }.to raise_error(Connections::ProductSources::Error) { |e| expect(e.code).to eq("missing_scopes") }
      expect(connection.reload.products_sync_error).to eq("missing_scopes")
    end
  end

  describe "money" do
    it "turns prices into whole centimes without a float" do
      expect([ "12.50", "12", 12, "0.1", "1999.99", "", nil, "abc" ].map { |value| Connections::ProductSources.cents(value) }).to eq([ 1250, 1200, 1200, 10, 199_999, nil, nil, nil ])
    end
  end

  describe "the connection" do
    it "keeps the API keys encrypted, readable only through api_credentials, and tells whether the catalog can be read" do
      connection = woo_connection
      expect(connection.api_credentials_ciphertext).not_to include("ck_synthetic")
      expect(connection.api_credentials).to eq({ "consumer_key" => "ck_synthetic", "consumer_secret" => "cs_synthetic" })
      expect(connection.products_importable?).to be(true)

      connection.update!(api_credentials: { consumer_key: "only-one" })
      expect(connection.products_importable?).to be(false)
      connection.update!(api_credentials: { consumer_key: "ck", consumer_secret: "cs" }, active: false)
      expect(connection.products_importable?).to be(false)
    end

    it "leaves the imported products in place, as manual ones, when the connection is deleted" do
      connection = woo_connection
      Connections::ProductImport.new(connection: connection, transport: transport([ "/products", json([ { id: 1, name: "Keep me", status: "publish", type: "simple", price: "10" } ], { "X-WP-TotalPages" => "1" }) ])).call
      product = connection.products.first

      connection.destroy!

      expect(product.reload.store_connection_id).to be_nil
      expect(Product.native.where(id: product.id)).to exist
    end
  end
end
