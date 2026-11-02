# frozen_string_literal: true

require "rails_helper"

RSpec.describe Platform::StoreReset do
  let(:password) { "synthetic-reset-password-123" }
  let!(:actor) { User.create!(email: "reset-owner-#{SecureRandom.hex(4)}@example.test", password: password, admin: true, super_admin: true) }
  let!(:store) { Store.create!(slug: "reset-#{SecureRandom.hex(5)}", name: "Synthetic test workspace", email: "owner@example.test", phone: "0612345678", currency: "MAD") }
  let!(:bystander) { Store.create!(slug: "keep-#{SecureRandom.hex(5)}", name: "Synthetic bystander workspace", currency: "MAD") }
  let!(:merchant) { store.users.create!(email: "merchant-#{SecureRandom.hex(4)}@example.test", password: password, admin: true) }
  let!(:bystander_admin) { bystander.users.create!(email: "bystander-#{SecureRandom.hex(4)}@example.test", password: password, admin: true) }

  def count_for(table, store_id)
    ActiveRecord::Base.connection.select_value("SELECT COUNT(*) FROM #{table} WHERE store_id = #{store_id.to_i}").to_i
  end

  # One record in every store-owned table that has a model, plus a Meta connection.
  def populate(workspace)
    workspace.install_online_store_defaults!
    customer = workspace.customers.create!(name: "Synthetic buyer", phone: "0612345678", city: "Casablanca")
    customer.addresses.create!(city: "Casablanca", line1: "Synthetic address")
    product = workspace.products.create!(name: "Synthetic product", slug: "synthetic-product", status: "active", price_cents: 101, stock: 5, track_inventory: false)
    variant = product.product_variants.create!(name: "M", stock: 2)
    collection = workspace.collections.create!(name: "Synthetic collection")
    collection.collection_products.create!(product: product)
    workspace.discounts.create!(code: "TEST10", discount_type: "percent", value: 10)
    workspace.store_expenses.create!(spent_on: Date.current, category: "rent", amount_cents: 500)
    cart = workspace.carts.create!(token: SecureRandom.hex(8))
    cart.cart_items.create!(product: product, product_variant: variant, quantity: 1, unit_price_cents: 101)

    order = workspace.orders.create!(customer: customer, customer_name: customer.name, customer_phone: customer.phone,
      customer_city: customer.city, customer_address: "Synthetic address", total_cents: 101, subtotal_cents: 101,
      currency: "MAD", status: "new")
    order.order_items.create!(product: product, product_variant: variant, product_name: product.name, quantity: 1, unit_price_cents: 101, total_cents: 101)
    order.order_events.create!(kind: "comment", body: "Synthetic note")
    order.inventory_movements.create!(product: product, product_variant: variant, quantity: -1, reason: "order_confirmed")

    connection = workspace.store_connections.create!(name: "Synthetic Shopify", provider: "shopify", external_domain: "#{workspace.slug}.myshopify.com", shopify_oauth: true)
    connection.external_order_receipts.create!(order: order, external_id: "ext-1", status: "accepted", received_at: Time.current)

    ShopifyPrivacyRequest.create!(store_connection: connection, event_key: "event-#{SecureRandom.hex(6)}", topic: "customers/data_request")
    SealloConnectionCode.create!(store: workspace, user: workspace.users.first, digest: SecureRandom.hex(16), expires_at: 1.hour.from_now)
    WoocommerceConnectionCode.create!(store: workspace, user: workspace.users.first, digest: SecureRandom.hex(16),
      site_domain: "#{workspace.slug}.example.test", code_challenge: SecureRandom.alphanumeric(43), expires_at: 1.hour.from_now)

    account = AdvertisingAccount.create!(store: workspace, name: "Synthetic ads", provider: "Meta")
    campaign = account.advertising_campaigns.create!(name: "Synthetic campaign")
    campaign.advertising_performances.create!(date: Date.current)
    ActiveRecord::Base.connection.execute("INSERT INTO meta_ads_connections (store_id, status, created_at, updated_at) VALUES (#{workspace.id}, 'disconnected', now(), now())")

    OauthAccessToken.create!(store: workspace, token_digest: SecureRandom.hex(8), refresh_digest: SecureRandom.hex(8), client_id: "synthetic",
      expires_at: 1.day.from_now, refresh_expires_at: 1.day.from_now)
    PushSubscription.create!(store: workspace, user: workspace.users.first, endpoint: "https://push.example.test/#{SecureRandom.hex(4)}", p256dh: "p256dh", auth: "auth")
    ConfirmationShift.create!(store: workspace, user: workspace.users.first, actor_label: "Synthetic agent", started_at: Time.current)
    workspace.agent_changesets.create!(summary: "Synthetic changeset")
    workspace.invoices.create!(period_starts_on: Date.current, period_ends_on: 1.month.from_now.to_date)
    workspace.update!(tagline: "Synthetic tagline", whatsapp: "0612345678", shipping_dh: 40, free_shipping_threshold_dh: 300, low_stock_threshold: 9,
      sendit_public_key: "synthetic-public", sendit_secret_key: "synthetic-secret", discord_orders_webhook_url: "https://discord.example.test/hook",
      meta_pixel_id: "1234567890", legal_entity_name: "Synthetic LLC", admin_theme: (Store::ADMIN_THEMES - [ Store.column_defaults["admin_theme"] ]).first, sendit_allow_open: false)
    workspace.generate_api_token!
    order
  end

  def reset!(target = store, user = actor, confirmation: target.slug)
    described_class.new(store: target, actor: user).call(confirmation: confirmation)
  end

  context "with a populated workspace" do
    before do
      populate(store)
      populate(bystander)
    end

    it "empties every store-owned table that is not rebuilt from defaults" do
      reset!

      (described_class::CLEARED_TABLES - %w[home_sections pages menu_items]).each do |table|
        expect(count_for(table, store.id)).to eq(0), "#{table} still holds rows for the reset workspace"
      end
    end

    it "leaves the workspace looking freshly provisioned" do
      fresh = Store.create!(slug: "fresh-#{SecureRandom.hex(5)}", name: "Synthetic fresh workspace", currency: "MAD")
      fresh.install_online_store_defaults!

      reset!

      expect(store.home_sections.count).to eq(fresh.home_sections.count)
      expect(store.pages.pluck(:slug).sort).to eq(fresh.pages.pluck(:slug).sort)
      expect(store.menu_items.count).to eq(fresh.menu_items.count)
      expect(store.translations.count).to eq(0)
      expect(store.orders.count + store.customers.count + store.products.count + store.collections.count).to eq(0)
    end

    it "puts settings back to their defaults and keeps identity, billing, staff and invoices" do
      invoices = store.invoices.count
      reset!
      store.reload

      expect(store.attributes.slice(*described_class::RESET_SETTINGS)).to eq(described_class::RESET_SETTINGS.index_with { |a| Store.column_defaults[a] })
      expect(store.api_token_digest).to be_nil
      expect([ store.name, store.email, store.phone, store.currency ]).to eq([ "Synthetic test workspace", "owner@example.test", "0612345678", "MAD" ])
      expect(store.users).to contain_exactly(merchant)
      expect(store.invoices.count).to eq(invoices)
    end

    it "keeps Shopify privacy requests as compliance records, detached from the removed connection" do
      request = ShopifyPrivacyRequest.find_by!(store_connection_id: store.store_connections.select(:id))

      reset!

      expect(request.reload.store_connection_id).to be_nil
      expect(ShopifyPrivacyRequest.where(store_connection_id: bystander.store_connections.select(:id)).count).to eq(1)
    end

    it "does not touch any other workspace" do
      before = %w[orders customers products collections carts discounts store_expenses store_connections pages home_sections menu_items oauth_access_tokens].index_with { |table| count_for(table, bystander.id) }
      tagline = bystander.reload.tagline

      reset!

      expect(before.keys.index_with { |table| count_for(table, bystander.id) }).to eq(before)
      expect(count_for("meta_ads_connections", bystander.id)).to eq(1)
      expect(bystander.reload.tagline).to eq(tagline)
      expect(bystander.api_token_digest).to be_present
    end

    it "writes one audit event with the counts that were erased" do
      expect { reset! }.to change { AuditEvent.where(action: "store.reset", store_id: store.id).count }.by(1)

      event = AuditEvent.where(action: "store.reset", store_id: store.id).last
      expect(event.actor_user).to eq(actor)
      expect(event.metadata).to include("orders" => 1, "customers" => 1, "products" => 1, "collections" => 1, "connections" => 1, "slug" => store.slug)
    end

    it "accepts the slug in any case with surrounding spaces" do
      expect { reset!(confirmation: "  #{store.slug.upcase} ") }.not_to raise_error
      expect(store.orders.count).to eq(0)
    end

    it "rolls everything back when the defaults cannot be reinstalled" do
      allow(store).to receive(:install_online_store_defaults!).and_raise(ActiveRecord::StatementInvalid, "synthetic failure")

      expect { reset! }.to raise_error(ActiveRecord::StatementInvalid)

      expect(store.reload.orders.count).to eq(1)
      expect(store.products.count).to eq(1)
      expect(store.tagline).to eq("Synthetic tagline")
      expect(AuditEvent.where(action: "store.reset", store_id: store.id)).to be_empty
    end

    it "reinstalls no storefront content when the storefront is disabled" do
      store.update!(storefront_enabled: false)

      reset!

      expect([ store.home_sections.count, store.pages.count, store.menu_items.count ]).to eq([ 0, 0, 0 ])
    end

    it "refuses a wrong confirmation and changes nothing" do
      expect { reset!(confirmation: "not-the-slug") }.to raise_error(described_class::Denied) { |e| expect(e.reason).to eq(:confirmation_mismatch) }
      expect { reset!(confirmation: "") }.to raise_error(described_class::Denied)

      expect(store.reload.orders.count).to eq(1)
      expect(AuditEvent.where(action: "store.reset", store_id: store.id)).to be_empty
    end

    it "refuses anyone who is not a super admin" do
      expect { reset!(store, merchant) }.to raise_error(described_class::Denied) { |e| expect(e.reason).to eq(:not_super_admin) }
      expect(store.reload.orders.count).to eq(1)
    end
  end

  it "classifies every store-owned table as cleared or kept" do
    connection = ActiveRecord::Base.connection
    store_owned = connection.tables.select { |table| table != "stores" && connection.column_exists?(table, :store_id) }
    classified = described_class::CLEARED_TABLES + described_class::KEPT_TABLES

    expect(store_owned - classified).to be_empty, "Add #{(store_owned - classified).join(', ')} to Platform::StoreReset::CLEARED_TABLES or KEPT_TABLES"
    expect(classified - store_owned).to be_empty, "Platform::StoreReset lists tables that no longer have a store_id: #{(classified - store_owned).join(', ')}"
    expect(described_class::CLEARED_TABLES & described_class::KEPT_TABLES).to be_empty
  end
end
