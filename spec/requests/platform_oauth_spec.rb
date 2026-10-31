# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Platform OAuth", type: :request do
  let(:password) { "synthetic-credential-123" }
  let!(:owner) { User.create!(email: "platform-oauth@example.test", password: password, admin: true, super_admin: true) }
  let!(:client) { OauthClient.register!(name: "Synthetic agent", redirect_uris: [ "https://agent.example.test/callback" ]) }
  let(:resource) { "http://#{Store.base_domain}/platform/mcp" }
  let(:verifier) { "v" * 64 }
  let(:query) do
    { client_id: client.client_id, redirect_uri: client.redirect_uris.first, response_type: "code",
      code_challenge: Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false),
      code_challenge_method: "S256", scope: "platform", resource: resource, state: "synthetic-state" }
  end

  before do
    host! Store.base_domain
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
  end

  def sign_in(user = owner)
    post "/admin/login", params: { email: user.email, password: password, workspace: user.store&.slug }
  end

  def consent_ticket(overrides = {})
    get "/platform/oauth/authorize", params: query.merge(overrides)
    expect(response).to have_http_status(:ok)
    Nokogiri::HTML(response.body).at_css('input[name="ticket"]')["value"]
  end

  def authorize_code
    ticket = consent_ticket
    post "/platform/oauth/authorize", params: { ticket: ticket, decision: "allow" }
    expect(response).to have_http_status(:see_other)
    URI.decode_www_form(URI.parse(response.location).query).to_h.fetch("code")
  end

  def exchange(code, overrides = {})
    post "/platform/oauth/token", params: { grant_type: "authorization_code", code: code,
      client_id: client.client_id, redirect_uri: client.redirect_uris.first, code_verifier: verifier,
      resource: resource }.merge(overrides)
  end

  it "advertises a distinct platform issuer and resource" do
    post "/platform/mcp", params: { jsonrpc: "2.0", id: 1, method: "tools/list" }, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(response.headers["WWW-Authenticate"]).to include("/.well-known/oauth-protected-resource/platform/mcp")
    get "/.well-known/oauth-protected-resource/platform/mcp"
    expect(response.parsed_body.fetch("resource")).to eq(resource)
    expect(response.parsed_body.fetch("authorization_servers")).to eq([ "http://#{Store.base_domain}/platform/oauth" ])
    get "/.well-known/oauth-authorization-server/platform/oauth"
    expect(response.parsed_body.fetch("scopes_supported")).to eq([ "platform" ])
    expect(response.parsed_body.fetch("code_challenge_methods_supported")).to eq([ "S256" ])
  end

  it "returns to platform consent after signing in without a store" do
    get "/platform/oauth/authorize", params: query
    expect(response).to redirect_to(admin_login_path)
    sign_in
    expect(response.location).to include("/platform/oauth/authorize")
    follow_redirect!
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Allow platform access")
  end

  it "exchanges and rotates grants, rejects replay, and keeps catalog access separate" do
    sign_in
    code = authorize_code
    exchange(code)
    expect(response).to have_http_status(:ok)
    tokens = response.parsed_body
    expect(tokens.fetch("scope")).to eq("platform")
    expect(response.headers["Cache-Control"]).to include("no-store")
    post "/platform/mcp", params: { jsonrpc: "2.0", id: 1, method: "tools/list" },
      headers: { "Authorization" => "Bearer #{tokens.fetch('access_token')}", "Accept" => "application/json, text/event-stream" }, as: :json
    expect(response).to have_http_status(:ok)
    post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "tools/list" },
      headers: { "Authorization" => "Bearer #{tokens.fetch('access_token')}" }, as: :json
    expect(response).to have_http_status(:unauthorized)
    exchange(code)
    expect(response.parsed_body.fetch("error")).to eq("invalid_grant")
    refresh = { grant_type: "refresh_token", refresh_token: tokens.fetch("refresh_token"), client_id: client.client_id, resource: resource }
    post "/platform/oauth/token", params: refresh
    expect(response).to have_http_status(:ok)
    post "/platform/oauth/token", params: refresh
    expect(response.parsed_body.fetch("error")).to eq("invalid_grant")
  end

  it "revokes OAuth access and refresh grants from platform settings" do
    sign_in
    exchange(authorize_code)
    tokens = response.parsed_body
    delete "/admin/platform/agent-api/connections"
    expect(response).to have_http_status(:see_other)
    expect(PlatformOauthToken.authenticate(tokens.fetch("access_token"))).to be_nil
    post "/platform/oauth/token", params: { grant_type: "refresh_token", refresh_token: tokens.fetch("refresh_token"), client_id: client.client_id }
    expect(response.parsed_body.fetch("error")).to eq("invalid_grant")
  end

  it "rejects invalid scope, resource, response type and PKCE" do
    sign_in
    [ { scope: "catalog" }, { resource: "http://#{Store.base_domain}/mcp" },
      { response_type: "token" }, { code_challenge_method: "plain" } ].each do |override|
      get "/platform/oauth/authorize", params: query.merge(override)
      expect(response).to have_http_status(:bad_request)
    end
    exchange(authorize_code, code_verifier: "wrong" * 10)
    expect(response.parsed_body.fetch("error")).to eq("invalid_grant")
  end

  it "denies merchants and does not accept catalog consent tickets" do
    store = Store.create!(slug: "oauth-merchant", name: "Synthetic store", currency: "MAD")
    merchant = store.users.create!(email: "merchant@example.test", password: password, admin: true)
    sign_in(merchant)
    get "/platform/oauth/authorize", params: query
    expect(response).to have_http_status(:forbidden)
    ticket = Oauth::Tickets.issue(query)
    post "/platform/oauth/authorize", params: { ticket: ticket, decision: "allow" }
    expect(response).to have_http_status(:bad_request)
  end

  it "requires explicit consent and returns denial with state" do
    sign_in
    ticket = consent_ticket
    expect { post "/platform/oauth/authorize", params: { ticket: ticket } }.not_to change(PlatformOauthCode, :count)
    expect(response).to have_http_status(:bad_request)
    post "/platform/oauth/authorize", params: { ticket: ticket, decision: "deny" }
    callback = URI.decode_www_form(URI.parse(response.location).query).to_h
    expect(callback).to include("error" => "access_denied", "state" => "synthetic-state")
  end
  context "with production CSRF checks" do
    around do |example|
      controller = PlatformOauth::AuthorizationsController
      original_protection = controller.allow_forgery_protection
      original_origin_check = controller.forgery_protection_origin_check
      controller.allow_forgery_protection = true
      controller.forgery_protection_origin_check = true
      example.run
    ensure
      controller.allow_forgery_protection = original_protection
      controller.forgery_protection_origin_check = original_origin_check
    end

    it "allows consent with the rendered token and same-origin browser headers" do
      sign_in
      ticket = consent_ticket
      expect(response.headers["Referrer-Policy"]).to eq("same-origin")
      token = Nokogiri::HTML(response.body).at_css('input[name="authenticity_token"]')["value"]
      post "/platform/oauth/authorize", params: { ticket: ticket, decision: "allow", authenticity_token: token },
        headers: { "Origin" => "http://#{Store.base_domain}" }
      expect(response).to have_http_status(:see_other)
      expect(URI.decode_www_form(URI.parse(response.location).query).to_h).to have_key("code")
    end

    it "still rejects cross-origin consent and missing CSRF tokens" do
      sign_in
      ticket = consent_ticket
      token = Nokogiri::HTML(response.body).at_css('input[name="authenticity_token"]')["value"]
      expect do
        post "/platform/oauth/authorize", params: { ticket: ticket, decision: "allow", authenticity_token: token },
          headers: { "Origin" => "https://untrusted.example.test" }
      end.not_to change(PlatformOauthCode, :count)
      expect(response).to have_http_status(:unprocessable_entity)
      expect do
        post "/platform/oauth/authorize", params: { ticket: ticket, decision: "allow" },
          headers: { "Origin" => "http://#{Store.base_domain}" }
      end.not_to change(PlatformOauthCode, :count)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

end
