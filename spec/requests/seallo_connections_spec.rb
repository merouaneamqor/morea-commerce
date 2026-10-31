# frozen_string_literal: true

require "rails_helper"
require "nokogiri"

RSpec.describe "Seallo Connect workspace boundary", type: :request do
  let(:secret) { "synthetic-seallo-bridge-key-for-tests-123456" }
  let(:password) { "synthetic-seallo-password-123" }
  let(:store) { Store.create!(slug: "seallo-request-#{SecureRandom.hex(5)}", name: "Synthetic request workspace", currency: "MAD", storefront_enabled: false) }
  let(:staff) { store.users.create!(email: "seallo-#{SecureRandom.hex(5)}@example.test", password: password, admin: true) }
  let(:shop) { "synthetic-#{SecureRandom.hex(5)}.myshopify.com" }
  let(:connection) do
    store.store_connections.create!(provider: "shopify", name: "Seallo test shop", external_domain: shop,
      shopify_oauth: true, shopify_app: "seallo_connect", shopify_api_verified_at: Time.current)
  end

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("SEALLO_BRIDGE_SECRET").and_return(secret)
    allow(Connections::SealloBridge).to receive(:entitlement).and_return(
      "active" => true, "current_period_start" => 1.day.ago.iso8601, "current_period_end" => 29.days.from_now.iso8601,
      "plan_name" => "Seallo Basic", "order_limit" => 19
    )
    host! Store.base_domain
  end

  def signed_post(operation, payload, timestamp: Time.current.to_i.to_s, signature: nil)
    body = JSON.generate(payload.merge(operation: operation))
    signed = signature || OpenSSL::HMAC.hexdigest("sha256", secret, "#{timestamp}\n#{body}")
    post "/api/seallo/#{operation}", params: body, headers: {
      "CONTENT_TYPE" => "application/json", "X-Seallo-Timestamp" => timestamp, "X-Seallo-Signature" => signed
    }
  end

  def sign_in(user = staff, host = "#{store.slug}.#{Store.base_domain}")
    host! host
    post "/admin/login", params: { email: user.email, password: password }
    expect(response).to have_http_status(:redirect)
  end

  it "requires Morea sign-in before offering a connection code" do
    get "/admin/seallo/connect"
    expect(response).to redirect_to(admin_login_path)
    post "/admin/seallo/connect"
    expect(response).to redirect_to(admin_login_path)
    expect(SealloConnectionCode.count).to eq(0)
  end

  it "issues a private, expiring code for the authenticated workspace and ignores submitted store IDs" do
    foreign = Store.create!(slug: "seallo-foreign-#{SecureRandom.hex(5)}", name: "Foreign workspace", currency: "MAD")
    sign_in
    post "/admin/seallo/connect", params: { store_id: foreign.id, user_id: 999_999 }
    expect(response).to have_http_status(:ok)
    expect(response.headers["Cache-Control"]).to include("no-store")
    plaintext = Nokogiri::HTML(response.body).at_css("code").text.strip
    expect(plaintext).to match(/\A[0-9a-f]{48}\z/)
    record = SealloConnectionCode.find_by!(digest: Digest::SHA256.hexdigest(plaintext))
    expect(record.store_id).to eq(store.id)
    expect(record.user_id).to eq(staff.id)
    expect(record.expires_at).to be_within(2.seconds).of(10.minutes.from_now)
    expect(record.attributes.values).not_to include(plaintext)
    expect(foreign.store_connections).to be_empty
  end

  it "rejects a platform-only session with no workspace" do
    platform_user = User.create!(email: "seallo-platform-#{SecureRandom.hex(5)}@example.test", password: password, super_admin: true, admin: true)
    sign_in(platform_user, Store.base_domain)
    get "/admin/seallo/connect"
    expect(response).to have_http_status(:not_found)
    post "/admin/seallo/connect"
    expect(response).to have_http_status(:not_found)
    expect(SealloConnectionCode.count).to eq(0)
  end

  it "keeps confirmation agents out of the connection workflow" do
    agent = store.users.create!(email: "seallo-agent-#{SecureRandom.hex(5)}@example.test", password: password, confirmation_role: "agent")
    sign_in(agent)
    post "/admin/seallo/connect"
    expect(response).to redirect_to(home_admin_confirmations_path)
    expect(SealloConnectionCode.count).to eq(0)
  end

  it "requires a current signed bridge envelope for every API action" do
    connection
    %w[connect status sync disconnect].each do |operation|
      signed_post(operation, { shop: shop }, signature: "0" * 64)
      expect(response).to have_http_status(:unauthorized)
      signed_post(operation, { shop: shop }, timestamp: 301.seconds.ago.to_i.to_s)
      expect(response).to have_http_status(:unauthorized)
    end
    expect(connection.reload).to be_active
    expect(ShopifyOrdersSyncJob).not_to have_been_enqueued
  end

  it "links the signed Shopify shop to the code's workspace rather than submitted workspace IDs" do
    code = SealloConnectionCode.issue!(store: store, user: staff)
    allow(Connections::SealloBridge).to receive(:graphql).and_return(
      "shop" => { "myshopifyDomain" => shop }, "currentAppInstallation" => { "accessScopes" => [ { "handle" => "read_orders" } ] }
    )
    signed_post("connect", { code: code, shop: shop, store_id: 999_999 })
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include("connected" => true, "workspace_name" => store.name)
    saved = store.store_connections.find_by!(external_domain: shop)
    expect(ShopifyOrdersSyncJob).to have_been_enqueued.with(saved.id)
    expect(response.body).not_to include(code, "shopify_access_token", "shopify_refresh_token", secret)
  end

  it "reports only the new app's matching shop and does not expose legacy Shopify connections" do
    legacy = store.store_connections.create!(provider: "shopify", name: "Legacy app", external_domain: shop, shopify_oauth: true)
    signed_post("status", { shop: shop, connection_id: legacy.id })
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq("connected" => false, "state" => "unlinked")
    signed_post("disconnect", { shop: shop, connection_id: legacy.id })
    expect(response).to have_http_status(:ok)
    expect(legacy.reload).to be_active
  end

  it "queues a sync only for the signed shop and obeys its Shopify entitlement" do
    connection
    signed_post("sync", { shop: shop, store_id: 999_999 })
    expect(response).to have_http_status(:ok)
    expect(ShopifyOrdersSyncJob).to have_been_enqueued.with(connection.id)
    clear_enqueued_jobs
    store.update!(subscription_required: true, billing_status: "past_due")
    allow(Connections::SealloBridge).to receive(:entitlement).and_return("active" => false)
    signed_post("sync", { shop: shop })
    expect(response).to have_http_status(:payment_required)
    expect(ShopifyOrdersSyncJob).not_to have_been_enqueued
  end

  it "disconnects only Seallo Connect and prevents subsequent sync" do
    connection
    other = store.store_connections.create!(provider: "shopify", name: "Other app shop", external_domain: "legacy-#{SecureRandom.hex(5)}.myshopify.com", shopify_oauth: true)
    signed_post("disconnect", { shop: shop, connection_id: other.id })
    expect(response).to have_http_status(:ok)
    expect(connection.reload).not_to be_active
    expect(connection.shopify_api_verified_at).to be_nil
    expect(other.reload).to be_active
    signed_post("sync", { shop: shop })
    expect(response).to have_http_status(:conflict)
    expect(ShopifyOrdersSyncJob).not_to have_been_enqueued
  end

  it "rejects replaying a signed status envelope at a destructive endpoint" do
    connection
    body = JSON.generate(operation: "status", shop: shop)
    timestamp = Time.current.to_i.to_s
    signature = OpenSSL::HMAC.hexdigest("sha256", secret, "#{timestamp}\n#{body}")
    post "/api/seallo/disconnect", params: body, headers: {
      "CONTENT_TYPE" => "application/json", "X-Seallo-Timestamp" => timestamp, "X-Seallo-Signature" => signature
    }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(connection.reload).to be_active
  end

  def privacy_request(attributes = {})
    ShopifyPrivacyRequest.create!({ store_connection: connection, event_key: "synthetic-#{SecureRandom.hex(12)}",
      topic: "customers/data_request", status: "needs_review", error_code: "secure_response_required",
      identifiers: { "request_id" => "synthetic-request", "customer_id" => "synthetic-customer", "order_ids" => [] } }.merge(attributes))
  end

  it "lists and securely exports only this workspace's privacy request" do
    record = privacy_request
    sign_in
    get "/admin/shopify_privacy_requests"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(record.id.to_s)
    get "/admin/shopify_privacy_requests/#{record.id}/export"
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/json")
    expect(response.headers["Cache-Control"]).to include("no-store")
    expect(response.headers["Content-Disposition"]).to include("attachment")
    expect(response.parsed_body).to include("request_id" => "synthetic-request", "orders" => [])
  end

  it "rejects another workspace's privacy request on every member route" do
    foreign_store = Store.create!(slug: "seallo-privacy-other-#{SecureRandom.hex(5)}", name: "Other privacy workspace", currency: "MAD")
    foreign_connection = foreign_store.store_connections.create!(provider: "shopify", name: "Other shop", external_domain: "other-#{SecureRandom.hex(5)}.myshopify.com", shopify_app: "seallo_connect", shopify_oauth: true)
    foreign_request = privacy_request(store_connection: foreign_connection)
    sign_in
    get "/admin/shopify_privacy_requests/#{foreign_request.id}"
    expect(response).to have_http_status(:not_found)
    get "/admin/shopify_privacy_requests/#{foreign_request.id}/export"
    expect(response).to have_http_status(:not_found)
    post "/admin/shopify_privacy_requests/#{foreign_request.id}/complete"
    expect(response).to have_http_status(:not_found)
    post "/admin/shopify_privacy_requests/#{foreign_request.id}/retry_processing"
    expect(response).to have_http_status(:not_found)
    expect(foreign_request.reload.status).to eq("needs_review")
    expect(ShopifyPrivacyRequestJob).not_to have_been_enqueued
  end

  it "records fulfillment of a secure data response and clears its encrypted identifiers" do
    record = privacy_request
    sign_in
    post "/admin/shopify_privacy_requests/#{record.id}/complete"
    expect(response).to have_http_status(:see_other)
    expect(record.reload.status).to eq("completed")
    expect(record.identifiers_ciphertext).to be_nil
  end

  it "cannot mark unprocessed or retained redaction work complete" do
    sign_in
    [ { status: "pending", error_code: nil }, { status: "needs_review", error_code: "retained_business_records" } ].each do |attributes|
      record = privacy_request(attributes.merge(topic: "customers/redact"))
      original_identifiers = record.identifiers_ciphertext
      post "/admin/shopify_privacy_requests/#{record.id}/complete"
      expect(response).to have_http_status(:see_other)
      expect(record.reload.status).to eq(attributes[:status])
      expect(record.identifiers_ciphertext).to eq(original_identifiers)
    end
  end

  it "does not expose a redaction request as a customer data export" do
    record = privacy_request(topic: "customers/redact")
    sign_in
    get "/admin/shopify_privacy_requests/#{record.id}/export"
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).not_to include("synthetic-customer")
  end

  it "renders connection and privacy screens in French, English and Arabic with inherited RTL" do
    data_request = privacy_request
    retained = privacy_request(topic: "customers/redact", error_code: "retained_business_records")
    shop_request = privacy_request(topic: "shop/redact", status: "pending", error_code: nil)
    connection.update!(shopify_sync_state: "catching_up")
    sign_in
    %w[fr en ar].each do |locale|
      paths = [ "/admin/seallo/connect", "/admin/shopify_privacy_requests",
        "/admin/shopify_privacy_requests/#{data_request.id}", "/admin/shopify_privacy_requests/#{retained.id}",
        "/admin/shopify_privacy_requests/#{shop_request.id}" ]
      paths.each do |path|
        get path, params: { locale: locale }
        expect(response).to have_http_status(:ok)
        document = Nokogiri::HTML(response.body)
        expect(document.at_css("html")["dir"]).to eq(locale == "ar" ? "rtl" : "ltr")
        expect(document.at_css(".translation_missing")).to be_nil
        expect(response.body).not_to include("Translation missing", "translation missing")
      end
      post "/admin/seallo/connect", params: { locale: locale }
      expect(response).to have_http_status(:ok)
      document = Nokogiri::HTML(response.body)
      expect(document.at_css(".translation_missing")).to be_nil
      expect(document.at_css("code")["dir"]).to eq("ltr")
      expect(document.at_css("html")["dir"]).to eq(locale == "ar" ? "rtl" : "ltr")
    end
  end

  it "keeps authorized privacy handling available after the workspace subscription expires" do
    record = privacy_request
    store.update!(subscription_required: true, billing_status: "past_due")
    sign_in
    get "/admin/shopify_privacy_requests"
    expect(response).to have_http_status(:ok)
    get "/admin/shopify_privacy_requests/#{record.id}"
    expect(response).to have_http_status(:ok)
    get "/admin/shopify_privacy_requests/#{record.id}/export"
    expect(response).to have_http_status(:ok)
    post "/admin/shopify_privacy_requests/#{record.id}/complete"
    expect(response).to have_http_status(:see_other)
    expect(record.reload.status).to eq("completed")
  end
end
