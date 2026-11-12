require "rails_helper"
require "nokogiri"

RSpec.describe "Products of the connected stores", type: :request do
  include ActiveJob::TestHelper

  let(:password) { "synthetic-password-123" }
  let(:store) { Store.create!(slug: "ps-#{SecureRandom.hex(5)}", name: "Walkfit", currency: "MAD") }
  let(:owner) { store.users.create!(name: "Owner", email: "owner-#{SecureRandom.hex(4)}@example.test", password: password, admin: true) }
  let(:secret) { "synthetic-webhook-secret" }
  let!(:woo) { store.store_connections.create!(provider: "woocommerce", name: "Woo shop", external_domain: "woo-#{SecureRandom.hex(3)}.example.test", webhook_secret: secret) }
  let!(:youcan) { store.store_connections.create!(provider: "youcan", name: "YouCan shop", external_domain: "yc-#{SecureRandom.hex(3)}.example.test", external_store_id: SecureRandom.uuid, webhook_secret: secret) }

  def sign_in(user = owner)
    host! "#{store.slug}.#{Store.base_domain}"
    post "/admin/login", params: { email: user.email, password: password }
  end

  def document = Nokogiri::HTML(response.body)

  def product(name, connection: nil, status: "active", **attrs)
    store.products.create!(name: name, price_cents: 10_000, status: status, store_connection: connection, external_id: (SecureRandom.hex(3) if connection), **attrs)
  end

  before do
    product("Manual Tee")
    product("Woo Hoodie", connection: woo)
    product("Woo Cap", connection: woo)
    product("YouCan Shoe", connection: youcan)
  end

  describe "the products page" do
    before { sign_in }

    it "shows every visible product with its source, and a chooser of the manual products and the active stores" do
      get "/admin/products"

      sources = document.css("tbody tr [data-source]").map { |cell| cell.text.squish }
      expect(sources.sort).to eq([ "Manuel", "Woo shop", "Woo shop", "YouCan shop" ].sort).or eq([ "Manual", "Woo shop", "Woo shop", "YouCan shop" ].sort)
      chips = document.css("[data-store-chooser] a")
      expect(chips.map { |chip| chip["data-source"] }).to eq([ "all", "manual", woo.id.to_s, youcan.id.to_s ])
      expect(chips.map { |chip| chip.text.squish }.last(2)).to eq([ "Woo shop woocommerce · 2", "YouCan shop youcan · 1" ])
      expect(chips.first.text.squish).to match(/4\z/)
      expect(chips[1].text.squish).to match(/1\z/)
    end

    it "shows only the products of the store that is chosen, or only the manual ones" do
      get "/admin/products", params: { source: woo.id }
      expect(document.css("tbody tr .admin-link").map { |link| link.text.squish }).to contain_exactly("Woo Hoodie", "Woo Cap")
      expect(document.at_css("[data-store-chooser] a[aria-current=true]")["data-source"]).to eq(woo.id.to_s)

      get "/admin/products", params: { source: "manual" }
      expect(document.css("tbody tr .admin-link").map { |link| link.text.squish }).to eq([ "Manual Tee" ])
    end

    it "hides the products of a store that is switched off, everywhere, and lists only the active stores in the chooser" do
      woo.update!(active: false)

      get "/admin/products"
      expect(document.css("tbody tr .admin-link").map { |link| link.text.squish }).to contain_exactly("Manual Tee", "YouCan Shoe")
      expect(document.css("[data-store-chooser] a").map { |chip| chip["data-source"] }).to eq([ "all", "manual", youcan.id.to_s ])

      get "/admin/products", params: { source: woo.id }                       # a switched-off store cannot be opened
      expect(response).to have_http_status(:not_found)

      get "/admin/orders/product_search", params: { q: "woo" }
      expect(JSON.parse(response.body)).to eq([])                              # nor sold from the order form
      get "/admin/orders/product_search", params: { q: "youcan" }
      expect(JSON.parse(response.body).map { |item| item["label"] }).to eq([ "YouCan Shoe" ])

      woo.update!(active: true)
      get "/admin/orders/product_search", params: { q: "woo" }
      expect(JSON.parse(response.body).map { |item| item["label"] }).to contain_exactly("Woo Cap", "Woo Hoodie")   # back when it is switched on again
    end

    it "does not offer another store's connection" do
      foreign = Store.create!(slug: "foreign-#{SecureRandom.hex(4)}", name: "Other", currency: "MAD")
      stranger = foreign.store_connections.create!(provider: "woocommerce", name: "Foreign woo", external_domain: "f-#{SecureRandom.hex(3)}.example.test", webhook_secret: secret)

      get "/admin/products", params: { source: stranger.id }

      expect(response).to have_http_status(:not_found)
    end

    it "counts the low stock of the visible products only" do
      # every product tracks its stock at 0 here (the default), so all of them are low: 4 visible, then 2 once Woo is switched off
      woo.products.update_all(track_inventory: true, stock: 1)
      get "/dashboard"
      expect(document.at_css("[data-low-stock-count]").text.squish).to eq("4")

      woo.update!(active: false)
      get "/dashboard"
      expect(document.at_css("[data-low-stock-count]").text.squish).to eq("2")
      expect(document.css("[data-low-stock-item]").map { |row| row.text.squish }.join).not_to include("Woo")
    end
  end

  describe "the public storefront" do
    it "never sells the catalog imported from another store" do
      store.update!(storefront_enabled: true)
      host! "#{store.slug}.#{Store.base_domain}"

      get "/en/search", params: { q: "Hoodie" }
      expect(response.body).not_to include("Woo Hoodie")
      get "/en/search", params: { q: "Manual" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Manual Tee")
      get "/en/products/#{store.products.find_by!(name: "Woo Hoodie").slug}"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "the connection page" do
    before { sign_in }

    it "keeps the API keys hidden, saves them encrypted, and keeps a key that is left blank" do
      get "/admin/store_connections/#{woo.id}"
      expect(document.at_css("[data-products-sync]")).to be_present
      expect(document.at_css("[data-sync-state]")["data-sync-state"]).to eq("never")
      expect(document.at_css("form[data-api-credentials] input[name='store_connection[consumer_key]']")["value"]).to be_nil
      expect(document.at_css("[data-products-sync] button[disabled]")).to be_present      # no keys yet: nothing to sync

      patch "/admin/store_connections/#{woo.id}", params: { operation: "save_api_credentials", store_connection: { consumer_key: "ck_new", consumer_secret: "cs_new" } }
      expect(response).to have_http_status(:see_other)
      expect(woo.reload.api_credentials).to eq({ "consumer_key" => "ck_new", "consumer_secret" => "cs_new" })
      expect(woo.api_credentials_ciphertext).not_to include("ck_new")

      patch "/admin/store_connections/#{woo.id}", params: { operation: "save_api_credentials", store_connection: { consumer_key: "ck_rotated", consumer_secret: "" } }
      expect(woo.reload.api_credentials).to eq({ "consumer_key" => "ck_rotated", "consumer_secret" => "cs_new" })

      get "/admin/store_connections/#{woo.id}"
      expect(response.body).not_to include("ck_rotated", "cs_new")
      expect(document.at_css("[data-products-sync] button[disabled]")).to be_nil           # ready now
    end

    it "queues a sync only when the store can be read, and shows how the last one went" do
      patch "/admin/store_connections/#{woo.id}", params: { operation: "sync_products" }
      expect(flash[:alert]).to be_present
      expect(enqueued_jobs.map { |job| job["job_class"] }).not_to include("ProductsSyncJob")

      woo.update!(api_credentials: { consumer_key: "ck", consumer_secret: "cs" })
      patch "/admin/store_connections/#{woo.id}", params: { operation: "sync_products" }
      expect(enqueued_jobs.map { |job| job["job_class"] }).to include("ProductsSyncJob")
      expect(woo.reload.products_sync_state).to eq("queued")

      woo.update!(products_sync_state: "ok", products_synced_at: Time.current, products_sync_counts: { "total" => 5, "created" => 3, "updated" => 2, "archived" => 0 })
      get "/admin/store_connections/#{woo.id}"
      expect(document.at_css("[data-sync-state]").text).to include("5 produits", "3 nouveaux")

      woo.update!(products_sync_state: "failed", products_sync_error: "invalid_credentials")
      get "/admin/store_connections/#{woo.id}"
      expect(document.at_css("[data-sync-state]").text).to include("Clés API refusées")
    end

    it "asks YouCan for its token, and never offers keys for a Shopify connection" do
      get "/admin/store_connections/#{youcan.id}"
      expect(document.css("form[data-api-credentials] input[type=password]").map { |input| input["name"] }).to eq([ "store_connection[access_token]" ])

      shopify = store.store_connections.create!(provider: "shopify", name: "Shopify", external_domain: "s-#{SecureRandom.hex(3)}.myshopify.com", shopify_oauth: true, webhook_secret: secret)
      patch "/admin/store_connections/#{shopify.id}", params: { operation: "save_api_credentials", store_connection: { access_token: "x" } }
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "ProductsSyncJob" do
    it "syncs every active connection that has its keys, and skips the others without failing" do
      woo.update!(api_credentials: { consumer_key: "ck", consumer_secret: "cs" })
      imports = []
      allow(Connections::ProductImport).to receive(:new) { |connection:, **| imports << connection.id; instance_double(Connections::ProductImport, call: nil) }

      ProductsSyncJob.perform_now

      expect(imports).to eq([ woo.id ])                                  # YouCan has no token yet

      allow(Connections::ProductImport).to receive(:new).and_raise(Connections::ProductSources::Error.new("unavailable"))
      expect { ProductsSyncJob.perform_now(woo.id) }.not_to raise_error
    end
  end
end
