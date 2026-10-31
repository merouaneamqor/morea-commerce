# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Superadmin MCP credentials", type: :request do
  let(:password) { "synthetic-credential-123" }
  let!(:owner) { User.create!(email: "platform-mcp-#{SecureRandom.hex(4)}@example.test", password: password, admin: true, super_admin: true) }
  let!(:store) { Store.create!(slug: "platform-mcp-#{SecureRandom.hex(4)}", name: "Synthetic MCP store", currency: "MAD") }
  let!(:merchant) { store.users.create!(email: "merchant-#{SecureRandom.hex(4)}@example.test", password: password, admin: true) }

  before { host! Store.base_domain }

  def sign_in(user)
    post "/admin/login", params: { email: user.email, password: password, workspace: user.store&.slug }
  end

  def discover(secret = nil)
    headers = { "Accept" => "application/json, text/event-stream" }
    headers["Authorization"] = "Bearer #{secret}" if secret
    post "/platform/mcp", params: { jsonrpc: "2.0", id: 1, method: "tools/list" }, headers: headers, as: :json
  end

  it "rejects missing, merchant and OAuth credentials" do
    discover
    expect(response).to have_http_status(:unauthorized)
    discover(store.generate_api_token!)
    expect(response).to have_http_status(:unauthorized)
    oauth, = OauthAccessToken.issue!(store: store, client_id: "synthetic-client")
    discover(oauth)
    expect(response).to have_http_status(:unauthorized)
  end

  it "accepts platform credentials and rechecks revocation and owner status" do
    secret = PlatformApiToken.issue!(user: owner)
    discover(secret)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("tools")
    owner.update!(status: "suspended")
    discover(secret)
    expect(response).to have_http_status(:unauthorized)
    owner.update!(status: "active")
    PlatformApiToken.where(user: owner).update_all(revoked_at: Time.current)
    discover(secret)
    expect(response).to have_http_status(:unauthorized)
  end

  it "does not grant platform tokens access to merchant APIs" do
    secret = PlatformApiToken.issue!(user: owner)
    post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "tools/list" }, headers: { "Authorization" => "Bearer #{secret}" }, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it "restricts the credential page and writes to superadmins" do
    get "/admin/platform/agent-api"
    expect(response).to redirect_to(admin_login_path)
    sign_in(merchant)
    get "/admin/platform/agent-api"
    expect(response).to redirect_to(admin_root_path)
    expect { post "/admin/platform/agent-api/token" }.not_to change(PlatformApiToken, :count)
    expect(response).to redirect_to(admin_root_path)
  end

  it "shows newly issued tokens only once and allows revocation" do
    sign_in(owner)
    post "/admin/platform/agent-api/token"
    expect(response).to have_http_status(:ok)
    expect(response.headers["Cache-Control"]).to include("no-store")
    secret = response.body[/morea_platform_[A-Za-z0-9_-]{43}/]
    expect(secret).to be_present
    expect(PlatformApiToken.authenticate(secret)&.user).to eq(owner)
    get "/admin/platform/agent-api"
    expect(response.body).not_to include(secret)
    delete "/admin/platform/agent-api/token"
    expect(response).to redirect_to(admin_platform_agent_api_path)
    expect(PlatformApiToken.authenticate(secret)).to be_nil
  end
end
