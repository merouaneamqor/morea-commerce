# frozen_string_literal: true

require "rails_helper"

RSpec.describe "WooCommerce plugin authorization", type: :request do
  let(:password) { "synthetic-woo-password-123" }
  let(:store) { Store.create!(slug: "woo-connect-#{SecureRandom.hex(5)}", name: "Synthetic Woo workspace", currency: "MAD", storefront_enabled: false) }
  let(:staff) { store.users.create!(email: "woo-#{SecureRandom.hex(5)}@example.test", password: password, admin: true) }
  let(:site) { "synthetic-#{SecureRandom.hex(4)}.example.test" }
  let(:verifier) { SecureRandom.urlsafe_base64(48) }
  let(:challenge) { Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false) }
  let(:return_to) { "https://#{site}/wp-admin/admin-post.php?action=seallo_wc_callback" }

  before { host! Store.base_domain }

  def sign_in(user = staff)
    host! "#{store.slug}.#{Store.base_domain}"
    post "/admin/login", params: { email: user.email, password: password }
    expect(response).to have_http_status(:redirect)
  end

  def authorization_params(overrides = {})
    { site: site, state: "synthetic-state-#{SecureRandom.hex(16)}", code_challenge: challenge, return_to: return_to }.merge(overrides)
  end

  def mint_code(params = authorization_params)
    sign_in
    post "/admin/woocommerce/connect", params: params
    expect(response).to have_http_status(:found)
    query = Rack::Utils.parse_query(URI.parse(response.location).query)
    [ query.fetch("code"), query.fetch("state") ]
  end

  def exchange(code:, code_verifier: verifier, site: self.site)
    host! Store.base_domain
    post "/api/woocommerce/connect", params: { code: code, code_verifier: code_verifier, site: site }.to_json,
      headers: { "CONTENT_TYPE" => "application/json" }
  end

  it "requires sign-in before offering or minting a code" do
    get "/admin/woocommerce/connect", params: authorization_params
    expect(response).to redirect_to(admin_login_path)
    post "/admin/woocommerce/connect", params: authorization_params
    expect(response).to redirect_to(admin_login_path)
    expect(WoocommerceConnectionCode.count).to eq(0)
  end

  it "shows the site on a confirmation page without minting a code on GET" do
    sign_in
    get "/admin/woocommerce/connect", params: authorization_params
    expect(response).to have_http_status(:ok)
    expect(response.headers["Cache-Control"]).to include("no-store")
    expect(response.body).to include(site)
    expect(response.body).not_to match(/\b[0-9a-f]{48}\b/)
    expect(WoocommerceConnectionCode.count).to eq(0)
  end

  it "rejects a callback that is not the plugin's own on the connecting site" do
    sign_in
    [
      "https://other.example.test/wp-admin/admin-post.php?action=seallo_wc_callback",
      "http://#{site}/wp-admin/admin-post.php?action=seallo_wc_callback",
      "https://#{site}/anything-else.php?action=seallo_wc_callback",
      "https://#{site}/wp-admin/admin-post.php?action=seallo_wc_callback&x=1",
      "https://user@#{site}/wp-admin/admin-post.php?action=seallo_wc_callback",
      "https://#{site}:8443/wp-admin/admin-post.php?action=seallo_wc_callback",
      "https://#{site}/../wp-admin/admin-post.php?action=seallo_wc_callback"
    ].each do |bad|
      post "/admin/woocommerce/connect", params: authorization_params(return_to: bad)
      expect(response).to have_http_status(:bad_request)
    end
    post "/admin/woocommerce/connect", params: authorization_params(code_challenge: "short")
    expect(response).to have_http_status(:bad_request)
    expect(WoocommerceConnectionCode.count).to eq(0)
  end

  it "mints a code on POST, returns the state unchanged and stores only a digest" do
    params = authorization_params
    code, state = mint_code(params)
    expect(state).to eq(params[:state])
    expect(response.location).to start_with("#{return_to}&")
    expect(code).to match(/\A[0-9a-f]{48}\z/)
    record = WoocommerceConnectionCode.sole
    expect(record.digest).to eq(Digest::SHA256.hexdigest(code))
    expect(record.site_domain).to eq(site)
  end

  it "exchanges the code for a delivery URL and a signing secret that intake accepts" do
    code, = mint_code
    exchange(code: code)
    expect(response).to have_http_status(:ok)
    expect(response.headers["Cache-Control"]).to include("no-store")
    body = JSON.parse(response.body)
    connection = store.store_connections.sole
    expect(connection).to have_attributes(provider: "woocommerce", external_domain: site, active: true, verified_at: nil)
    expect(body["secret"]).to match(/\A[0-9a-f]{64}\z/)
    expect(connection.webhook_secret).to eq(body["secret"])
    expect(body["delivery_url"]).to include("/webhooks/store_orders/#{connection.token}")
    expect(body["workspace_name"]).to eq(store.name)
  end

  it "consumes a code once" do
    code, = mint_code
    exchange(code: code)
    expect(response).to have_http_status(:ok)
    exchange(code: code)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JSON.parse(response.body)["error"]).to eq("invalid_code")
  end

  it "refuses a wrong PKCE verifier, a different site and a malformed code, leaving the code usable" do
    code, = mint_code
    exchange(code: code, code_verifier: SecureRandom.urlsafe_base64(48))
    expect(response).to have_http_status(:unprocessable_entity)
    exchange(code: code, site: "other-#{site}")
    expect(response).to have_http_status(:unprocessable_entity)
    exchange(code: "nope")
    expect(response).to have_http_status(:unprocessable_entity)
    expect(store.store_connections.count).to eq(0)
    exchange(code: code)
    expect(response).to have_http_status(:ok)
  end

  it "refuses an expired code and one whose issuer lost access" do
    code, = mint_code
    WoocommerceConnectionCode.sole.update!(expires_at: 1.minute.ago)
    exchange(code: code)
    expect(response).to have_http_status(:unprocessable_entity)

    code, = mint_code
    staff.update!(admin: false)
    exchange(code: code)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(store.store_connections.count).to eq(0)
  end

  it "re-linking the same site reactivates the connection and rotates its secret" do
    code, = mint_code
    exchange(code: code)
    first = JSON.parse(response.body)["secret"]
    connection = store.store_connections.sole
    connection.update!(active: false, verified_at: Time.current, last_error_code: "invalid_order")

    code, = mint_code
    exchange(code: code)
    second = JSON.parse(response.body)["secret"]
    expect(second).not_to eq(first)
    expect(store.store_connections.count).to eq(1)
    expect(connection.reload).to have_attributes(active: true, verified_at: nil, last_error_code: nil)
    expect(connection.webhook_secret).to eq(second)
  end
end
