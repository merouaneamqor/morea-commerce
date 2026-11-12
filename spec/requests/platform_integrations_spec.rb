# frozen_string_literal: true

require "rails_helper"
require "nokogiri"

RSpec.describe "Platform integration diagnostics", type: :request do
  let(:password) { "Synthetic-support-password-123!" }
  let!(:store) { Store.create!(slug: "pint-#{SecureRandom.hex(5)}", name: "Synthetic platform integrations", currency: "MAD", storefront_enabled: false) }
  let!(:actor) { User.create!(email: "pint-#{SecureRandom.hex(5)}@example.test", password: password, admin: true, super_admin: true) }
  let!(:connection) do
    store.store_connections.create!(provider: "shopify", name: "Synthetic Seallo", external_domain: "pint-#{SecureRandom.hex(5)}.myshopify.com",
      shopify_app: "seallo_connect", shopify_oauth: true, shopify_api_error_code: "invalid_response",
      shopify_sync_error: "private-upstream-secret")
  end
  let!(:woo) do
    store.store_connections.create!(provider: "woocommerce", name: "Synthetic Woo", external_domain: "woo-pint.example.test",
      webhook_secret: "synthetic-woo-signing-secret-99")
  end
  let!(:meta) { MetaAds::Connection.create!(store: store, access_token: "synthetic-meta-token", last_verified_at: 2.days.ago) }
  let(:index_path) { "/admin/platform/integrations" }
  let(:show_path) { "/admin/platform/integrations/#{store.id}" }

  before do
    host! Store.base_domain
    allow(Connections::SealloBridge).to receive(:entitlement).and_raise("Unexpected provider request")
    allow(Connections::SealloBridge).to receive(:graphql).and_raise("Unexpected provider request")
  end

  def sign_in(user = actor)
    post "/admin/login", params: { email: user.email, password: password }
    expect(response).to have_http_status(:redirect)
  end

  it "requires authentication" do
    get index_path
    expect(response).to redirect_to(admin_login_path)
    get show_path
    expect(response).to redirect_to(admin_login_path)
    post "#{show_path}/recheck", params: { kind: "store_connection", connection_id: connection.id, provider: "shopify" }
    expect(response).to redirect_to(admin_login_path)
  end

  it "rejects merchant administrators" do
    merchant = store.users.create!(email: "merchant-#{SecureRandom.hex(5)}@example.test", password: password, admin: true)
    host! "#{store.slug}.#{Store.base_domain}"
    sign_in(merchant)
    get index_path
    expect(response).to redirect_to(admin_root_path)
    post "#{show_path}/recheck", params: { kind: "store_connection", connection_id: connection.id, provider: "shopify" }
    expect(response).to redirect_to(admin_root_path)
    expect(Connections::SealloBridge).not_to have_received(:entitlement)
  end

  it "lists failing and connected workspaces without contacting providers or exposing secrets" do
    sign_in
    get index_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(store.name, connection.external_domain)
    expect(response.body).not_to include("private-upstream-secret", "synthetic-meta-token", "synthetic-woo-signing-secret")
    expect(Connections::SealloBridge).not_to have_received(:entitlement)
    expect(Connections::SealloBridge).not_to have_received(:graphql)
  end

  it "shows one workspace with turbo-confirmed recheck actions" do
    sign_in
    get show_path
    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    form = document.at_css("form[action='#{show_path}/recheck']")
    expect(form["method"]).to eq("post")
    expect(form["data-turbo-confirm"]).to be_present
    expect(response.body).to include("WooCommerce", "Meta Ads")
    expect(response.body).not_to include("private-upstream-secret", "synthetic-meta-token")
  end

  it "rechecks Seallo Shopify without importing orders and audits the action" do
    allow(Connections::SealloBridge).to receive(:entitlement).with(shop: connection.external_domain).and_return(
      "active" => true, "plan_name" => "Seallo Basic", "order_limit" => 30,
      "current_period_start" => 1.day.ago.iso8601, "current_period_end" => nil)
    api = instance_double(Connections::ShopifyApi, verify!: true)
    allow(Connections::ShopifyApi).to receive(:new).and_return(api)
    sign_in
    expect do
      post "#{show_path}/recheck", params: { kind: "store_connection", connection_id: connection.id, provider: "shopify" }
    end.not_to change { ActiveJob::Base.queue_adapter.enqueued_jobs.size }
    expect(response).to redirect_to(show_path)
    follow_redirect!
    expect(response.body).to include(I18n.t("platform_admin.integrations.outcomes.verified"))
    expect(api).to have_received(:verify!)
    event = AuditEvent.order(:id).last
    expect(event).to have_attributes(action: "integration.recheck", acting_as_platform: true)
    expect(event.metadata).to include("provider" => "shopify", "outcome" => "verified")
  end

  it "keeps disconnected Seallo shops inactive on recheck" do
    connection.update!(active: false)
    sign_in
    post "#{show_path}/recheck", params: { kind: "store_connection", connection_id: connection.id, provider: "shopify" }
    expect(response).to redirect_to(show_path)
    follow_redirect!
    expect(response.body).to include(I18n.t("platform_admin.integrations.outcomes.disconnected"))
    expect(connection.reload).not_to be_active
    expect(Connections::SealloBridge).not_to have_received(:entitlement)
  end

  it "refreshes WooCommerce local verified state without provider imports" do
    sign_in
    expect do
      post "#{show_path}/recheck", params: { kind: "store_connection", connection_id: woo.id, provider: "woocommerce" }
    end.not_to change { ActiveJob::Base.queue_adapter.enqueued_jobs.size }
    expect(response).to redirect_to(show_path)
    expect(woo.reload.verified_at).to be_present
    expect(woo.last_error_code).to be_nil
  end

  it "runs a Meta credential check without syncing ads" do
    client = instance_double(MetaAds::Client)
    allow(MetaAds::Client).to receive(:new).and_return(client)
    allow(client).to receive(:get).with("me", fields: "id").and_return(true)
    sign_in
    expect do
      post "#{show_path}/recheck", params: { kind: "meta_ads", connection_id: meta.id, provider: "meta_ads" }
    end.not_to change { ActiveJob::Base.queue_adapter.enqueued_jobs.size }
    expect(response).to redirect_to(show_path)
    expect(meta.reload.last_verified_at).to be_within(5.seconds).of(Time.current)
    expect(client).to have_received(:get).with("me", fields: "id")
  end

  it "supports a platform-only superadmin without a workspace" do
    expect(actor.store_id).to be_nil
    sign_in
    get index_path
    expect(response).to have_http_status(:ok)
    get show_path
    expect(response).to have_http_status(:ok)
  end
end
