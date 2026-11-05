# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Managing disconnected Shopify stores", type: :request do
  let(:suffix) { SecureRandom.hex(5) }
  let(:password) { "Synthetic-reconnect-#{suffix}-password" }
  let(:store) { Store.create!(slug: "reconnect-#{suffix}", name: "Synthetic workspace", currency: "MAD", storefront_enabled: false) }
  let(:owner) { store.users.create!(email: "owner-#{suffix}@example.test", password: password, admin: true) }
  let!(:connection) do
    store.store_connections.create!(name: "Old Shopify", provider: "shopify", external_domain: "old-#{suffix}.myshopify.com",
      shopify_oauth: true, shopify_app: "seallo_connect", active: false)
  end

  before do
    host! "#{store.slug}.#{Store.base_domain}"
    post admin_login_path, params: { email: owner.email, password: password }
  end

  it "offers Manage for disconnected current and retired Shopify app connections in each language" do
    legacy = store.store_connections.create!(name: "Retired Shopify", provider: "shopify", external_domain: "retired-#{suffix}.myshopify.com",
      shopify_oauth: true, active: false)
    %w[fr en ar].each do |locale|
      get admin_seallo_connect_path, params: { locale: locale }
      expect(response).to have_http_status(:ok)
      document = Nokogiri::HTML(response.body)
      [ connection, legacy ].each do |record|
        manage = document.at_css("a.admin-btn-secondary[href='#{admin_store_connection_path(record)}']")
        expect(manage.text).to eq(I18n.t("shopify_reconnect.manage", locale: locale))
      end
      expect(response.body).not_to match(/translation missing|translation_missing/i)
    end
  end

  it "guides reconnection through the existing shop's Shopify apps page without enabling it locally" do
    get admin_store_connection_path(connection)
    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    link = document.at_css("a[href='https://#{connection.external_domain}/admin/apps']")
    expect(link.text).to eq(I18n.t("shopify_reconnect.reconnect"))
    expect(link["rel"]).to include("noopener")
    expect(document.at_css("#shopify-reconnect-title")).to be_present
    expect(document.text).to include(store.name, connection.external_domain, I18n.t("shopify_reconnect.preserve_history"))
    expect(connection.reload).not_to be_active
  end

  it "does not fake OAuth authorization when an older client posts the reconnect operation" do
    expect(ShopifyOrdersSyncJob).not_to receive(:perform_later)
    post_path = admin_store_connection_path(connection)
    patch post_path, params: { operation: "reconnect", shop: "attacker.myshopify.com", return_to: "https://example.test" }
    expect(response).to have_http_status(:see_other)
    expect(response).to redirect_to("https://#{connection.external_domain}/admin/apps")
    expect(connection.reload).to have_attributes(active: false, shopify_api_verified_at: nil)
  end

  it "keeps manual signed webhook resumption working" do
    manual = store.store_connections.create!(name: "Signed Shopify", provider: "shopify", external_domain: "signed-#{suffix}.myshopify.com",
      webhook_secret: "synthetic-signing-secret", active: false)
    patch admin_store_connection_path(manual), params: { operation: "reconnect" }
    expect(response).to redirect_to(admin_store_connection_path(manual))
    expect(manual.reload).to be_active
  end

  it "does not manage or reconnect another workspace's record" do
    foreign = Store.create!(slug: "foreign-reconnect-#{suffix}", name: "Other workspace", currency: "MAD")
    other = foreign.store_connections.create!(name: "Other Shopify", provider: "shopify", external_domain: "foreign-#{suffix}.myshopify.com",
      shopify_oauth: true, active: false)
    patch admin_store_connection_path(other), params: { operation: "reconnect" }
    expect(response).to have_http_status(:not_found)
    expect(other.reload).not_to be_active
  end

  it "refuses an unsafe persisted destination" do
    StoreConnection.where(id: connection.id).update_all(external_domain: "example.test")
    patch admin_store_connection_path(connection), params: { operation: "reconnect" }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(connection.reload).not_to be_active
  end
end
