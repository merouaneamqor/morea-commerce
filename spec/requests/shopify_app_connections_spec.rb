# frozen_string_literal: true

require "rails_helper"
require "nokogiri"

RSpec.describe "Shared Shopify app connections", type: :request do
  let(:password) { "synthetic-shopify-password-123" }
  let(:app_secret) { "synthetic-shared-client-secret" }
  let(:store) { Store.create!(slug: "shopify-api-#{SecureRandom.hex(5)}", name: "Synthetic Shopify workspace", currency: "MAD", storefront_enabled: false) }
  let(:staff) { store.users.create!(email: "shopify-#{SecureRandom.hex(5)}@example.test", password: password, admin: true) }
  let(:attributes) { { name: "Shopify API", provider: "shopify", external_domain: "synthetic-#{SecureRandom.hex(5)}.myshopify.com" } }
  let(:connection) { store.store_connections.create!(attributes.merge(shopify_oauth: true)) }

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("SHOPIFY_CLIENT_ID").and_return("synthetic-shared-client-id")
    allow(ENV).to receive(:[]).with("SHOPIFY_CLIENT_SECRET").and_return(app_secret)
  end

  def sign_in(user = staff, host = "#{store.slug}.#{Store.base_domain}")
    host! host
    post "/admin/login", params: { email: user.email, password: password }
    expect(response).to have_http_status(:redirect)
  end

  def document
    Nokogiri::HTML(response.body)
  end

  def start_authorization
    patch "/admin/store_connections/#{connection.id}", params: { operation: "authorize_shopify" }
    expect(response).to have_http_status(:see_other)
    uri = URI.parse(response.location)
    expect(uri.host).to eq(connection.external_domain)
    Rack::Utils.parse_nested_query(uri.query).fetch("state")
  end

  def signed_callback(state:, shop: connection.external_domain, timestamp: Time.current.to_i)
    payload = { "shop" => shop, "code" => "synthetic-authorization-code", "timestamp" => timestamp.to_s, "state" => state }
    payload.merge("hmac" => OpenSSL::HMAC.hexdigest("sha256", app_secret, URI.encode_www_form(payload.sort)))
  end

  it "creates a tenant-owned connection and redirects to the shared app without contacting Shopify" do
    sign_in
    expect(Connections::ShopifyApi).not_to receive(:new)
    post "/admin/store_connections", params: { store_connection: attributes.merge(store_id: 999_999, active: false) }
    expect(response).to have_http_status(:see_other)
    saved = store.store_connections.find_by!(name: "Shopify API")
    expect(saved).to be_active
    expect(saved.shopify_oauth).to eq(true)
    expect(saved).not_to be_shopify_api_connected
    uri = URI.parse(response.location)
    expect(uri.scheme).to eq("https")
    expect(uri.host).to eq(saved.external_domain)
    expect(uri.path).to eq("/admin/oauth/authorize")
    query = Rack::Utils.parse_nested_query(uri.query)
    expect(query["client_id"]).to eq("synthetic-shared-client-id")
    expect(query["scope"].split(",")).to include("write_orders", "read_customers", "read_products")
    expect(query["redirect_uri"]).to include("/admin/shopify/callback")
    expect(query["state"]).to be_present
    expect(response.location).not_to include(app_secret)
  end

  it "renders installation without merchant credentials or webhooks in every language" do
    sign_in
    %w[fr en ar].each do |locale|
      [ "/admin/store_connections/new", "/admin/store_connections/#{connection.id}" ].each do |path|
        get path, params: { provider: "shopify", locale: locale }
        expect(response).to have_http_status(:ok)
        expect(document.at_css("html")["dir"]).to eq(locale == "ar" ? "rtl" : "ltr")
        expect(document.at_css(".translation_missing")).to be_nil
        expect(document.at_css("#webhook-url")).to be_nil
        oauth_form = if path.end_with?("/new")
          document.at_css("input[name='store_connection[provider]']").ancestors("form").first
        else
          document.at_css("input[name='operation'][value='authorize_shopify']").ancestors("form").first
        end
        expect(oauth_form["data-turbo"]).to eq("false")
        %w[webhook_secret shopify_client_id shopify_client_secret shopify_access_token].each do |field|
          expect(document.at_css("input[name='store_connection[#{field}]']")).to be_nil
        end
        expect(response.body).not_to include(app_secret)
      end
      expect(document.at_css("input[name='operation'][value='authorize_shopify']")).to be_present
      expect(document.at_css("input[name='operation'][value='verify_shopify_api']")).to be_nil
    end
  end

  it "offers an API test after installation without rendering stored tokens" do
    sign_in
    connection.update!(shopify_access_token: "synthetic-private-access-token", shopify_refresh_token: "synthetic-private-refresh-token",
      shopify_access_token_expires_at: 1.hour.from_now, shopify_refresh_token_expires_at: 30.days.from_now,
      shopify_granted_scopes: %w[write_orders read_customers read_products], shopify_api_verified_at: Time.current)
    get "/admin/store_connections/#{connection.id}", params: { locale: "en" }
    expect(response).to have_http_status(:ok)
    expect(document.at_css("input[name='operation'][value='verify_shopify_api']")).to be_present
    expect(document.at_css("input[name='operation'][value='authorize_shopify']").ancestors("form").first["data-turbo"]).to eq("false")
    expect(response.body).not_to include("synthetic-private-access-token", "synthetic-private-refresh-token", app_secret)
  end

  it "disables installation when the shared app is not configured" do
    allow(ENV).to receive(:[]).with("SHOPIFY_CLIENT_ID").and_return(nil)
    allow(ENV).to receive(:[]).with("SHOPIFY_CLIENT_SECRET").and_return(nil)
    sign_in
    get "/admin/store_connections/new", params: { provider: "shopify", locale: "en" }
    expect(response).to have_http_status(:ok)
    expect(document.css("button[disabled], input[type='submit'][disabled]")).not_to be_empty
    expect(Connections::ShopifyApi).not_to receive(:new)
    post "/admin/store_connections", params: { store_connection: attributes }
    expect(response).to have_http_status(422)
  end

  it "exchanges a valid callback once and rejects replay" do
    sign_in
    payload = signed_callback(state: start_authorization)
    service = instance_double(Connections::ShopifyApi)
    expect(Connections::ShopifyApi).to receive(:new).with(connection: connection).once.and_return(service)
    expect(service).to receive(:authorize!).with(code: "synthetic-authorization-code").once.and_return(true)
    get "/admin/shopify/callback", params: payload
    expect(response).to redirect_to(%r{/admin/store_connections/#{connection.id}})
    get "/admin/shopify/callback", params: payload
    expect(response).to have_http_status(422)
    expect(connection.reload.store_id).to eq(store.id)
  end

  it "accepts the registered apex callback after authorization starts on the tenant host" do
    sign_in
    payload = signed_callback(state: start_authorization)
    service = instance_double(Connections::ShopifyApi)
    expect(Connections::ShopifyApi).to receive(:new).with(connection: connection).and_return(service)
    expect(service).to receive(:authorize!).with(code: "synthetic-authorization-code").and_return(true)
    host! Store.base_domain
    get "/admin/shopify/callback", params: payload
    expect(response).to redirect_to(%r{/admin/store_connections/#{connection.id}})
    expect(connection.reload.shopify_oauth_state_digest).to be_nil
  end

  it "rejects expired signed timestamps and expired persisted authorization state" do
    sign_in
    expect(Connections::ShopifyApi).not_to receive(:new)
    payload = signed_callback(state: start_authorization, timestamp: 11.minutes.ago.to_i)
    get "/admin/shopify/callback", params: payload
    expect(response).to have_http_status(422)

    payload = signed_callback(state: start_authorization)
    connection.update!(shopify_oauth_state_expires_at: 1.second.ago)
    get "/admin/shopify/callback", params: payload
    expect(response).to have_http_status(422)
    expect(connection.reload.shopify_access_token).to be_blank
  end

  it "invalidates the previous nonce when another authorization starts" do
    sign_in
    previous = start_authorization
    latest = start_authorization
    expect(latest).not_to eq(previous)
    expect(connection.reload.shopify_oauth_state_digest).to eq(Digest::SHA256.hexdigest(latest))
    expect(Connections::ShopifyApi).not_to receive(:new)
    get "/admin/shopify/callback", params: signed_callback(state: previous)
    expect(response).to have_http_status(422)
  end

  it "disconnects by clearing encrypted credentials and invalidating outstanding authorization" do
    sign_in
    connection.update!(shopify_access_token: "synthetic-disconnect-access-token", shopify_refresh_token: "synthetic-disconnect-refresh-token",
      shopify_access_token_expires_at: 1.hour.from_now, shopify_refresh_token_expires_at: 30.days.from_now,
      shopify_granted_scopes: %w[write_orders read_customers read_products], shopify_api_verified_at: Time.current)
    payload = signed_callback(state: start_authorization)
    patch "/admin/store_connections/#{connection.id}", params: { operation: "disconnect" }
    expect(response).to have_http_status(:redirect)
    connection.reload
    expect(connection).not_to be_active
    expect(connection.shopify_access_token_ciphertext).to be_nil
    expect(connection.shopify_refresh_token_ciphertext).to be_nil
    expect(connection.shopify_access_token_expires_at).to be_nil
    expect(connection.shopify_refresh_token_expires_at).to be_nil
    expect(connection.shopify_api_verified_at).to be_nil
    expect(connection.shopify_granted_scopes).to be_empty
    expect(connection.shopify_oauth_state_digest).to be_nil
    expect(connection.shopify_oauth_state_expires_at).to be_nil
    expect(Connections::ShopifyApi).not_to receive(:new)
    get "/admin/shopify/callback", params: payload
    expect(response).to have_http_status(422)
  end

  it "keeps callback authorization values out of error page language links" do
    sign_in
    payload = signed_callback(state: start_authorization).merge("hmac" => "0" * 64)
    get "/admin/shopify/callback", params: payload
    expect(response).to have_http_status(422)
    links = document.css("[data-admin-language-switcher] a")
    expect(links.size).to eq(3)
    links.each do |link|
      uri = URI.parse(link["href"])
      query = Rack::Utils.parse_nested_query(uri.query)
      expect(query.keys & %w[code hmac state signature]).to be_empty
      expect(link["href"]).not_to include(payload["code"], payload["state"], payload["hmac"])
    end
  end

  it "rejects a mismatched state, tampered HMAC or different Shopify domain" do
    sign_in
    expect(Connections::ShopifyApi).not_to receive(:new)
    [ :state, :hmac, :shop ].each do |field|
      state = start_authorization
      payload = case field
      when :state then signed_callback(state: "unrelated-synthetic-state")
      when :hmac then signed_callback(state: state).merge("hmac" => "0" * 64)
      when :shop then signed_callback(state: state, shop: "another-synthetic.myshopify.com")
      end
      get "/admin/shopify/callback", params: payload
      expect(response).to have_http_status(422)
    end
  end

  it "rejects callbacks after the session changes merchant workspace" do
    sign_in
    payload = signed_callback(state: start_authorization)
    other = Store.create!(slug: "other-api-#{SecureRandom.hex(5)}", name: "Other synthetic workspace", currency: "MAD")
    other_staff = other.users.create!(email: "other-api-#{SecureRandom.hex(5)}@example.test", password: password, admin: true)
    sign_in(other_staff, "#{other.slug}.#{Store.base_domain}")
    expect(Connections::ShopifyApi).not_to receive(:new)
    get "/admin/shopify/callback", params: payload
    expect(response).to have_http_status(422)
    expect(connection.reload.shopify_access_token).to be_blank
  end

  it "verifies the API only on explicit request using the authorized connection" do
    sign_in
    service = instance_double(Connections::ShopifyApi, verify!: true)
    expect(Connections::ShopifyApi).to receive(:new).with(connection: connection).and_return(service)
    patch "/admin/store_connections/#{connection.id}", params: { operation: "verify_shopify_api" }
    expect(response).to redirect_to(%r{/admin/store_connections/#{connection.id}})
  end

  it "shows safe API failures without exposing the shared app secret" do
    sign_in
    service = instance_double(Connections::ShopifyApi)
    allow(Connections::ShopifyApi).to receive(:new).with(connection: connection).and_return(service)
    allow(service).to receive(:verify!) do
      connection.update!(shopify_api_error_code: "invalid_credentials")
      raise Connections::ShopifyApi::Error.new("invalid_credentials")
    end
    patch "/admin/store_connections/#{connection.id}", params: { operation: "verify_shopify_api" }
    expect(response).to have_http_status(422)
    expect(document.at_css("[role='alert']")).to be_present
    expect(connection.reload.shopify_api_error_code).to eq("invalid_credentials")
    expect(response.body).not_to include(app_secret)
  end

  it "hides foreign connection IDs for authorization and verification" do
    sign_in
    other = Store.create!(slug: "foreign-api-#{SecureRandom.hex(5)}", name: "Other synthetic workspace", currency: "MAD")
    foreign = other.store_connections.create!(attributes.merge(shopify_oauth: true))
    expect(Connections::ShopifyApi).not_to receive(:new)
    %w[authorize_shopify verify_shopify_api].each do |operation|
      patch "/admin/store_connections/#{foreign.id}", params: { operation: operation }
      expect(response).to have_http_status(:not_found)
    end
  end

  it "requires login for authorization, verification and callback" do
    host! "#{store.slug}.#{Store.base_domain}"
    %w[authorize_shopify verify_shopify_api].each do |operation|
      patch "/admin/store_connections/#{connection.id}", params: { operation: operation }
      expect(response).to have_http_status(:redirect)
    end
    get "/admin/shopify/callback", params: signed_callback(state: "unauthenticated-state")
    expect(response).to have_http_status(:redirect)
  end

  it "requires a merchant workspace for platform-only sessions" do
    root = User.create!(email: "platform-api-#{SecureRandom.hex(5)}@example.test", password: password, admin: true, super_admin: true)
    sign_in(root, Store.base_domain)
    %w[authorize_shopify verify_shopify_api].each do |operation|
      patch "/admin/store_connections/#{connection.id}", params: { operation: operation }
      expect(response).to have_http_status(:not_found)
    end
    get "/admin/shopify/callback", params: signed_callback(state: "platform-state")
    expect(response).to have_http_status(:not_found)
  end

  it "rejects Shopify operations on another provider" do
    sign_in
    woo = store.store_connections.create!(name: "Woo source", provider: "woocommerce", external_domain: "synthetic.example.test", webhook_secret: "synthetic-woo-signing-secret")
    expect(Connections::ShopifyApi).not_to receive(:new)
    %w[authorize_shopify verify_shopify_api].each do |operation|
      patch "/admin/store_connections/#{woo.id}", params: { operation: operation }
      expect(response).to have_http_status(422)
    end
  end
end
