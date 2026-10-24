# frozen_string_literal: true

require "rails_helper"
require "nokogiri"

RSpec.describe "Merchant sign in", type: :request do
  let(:password) { "synthetic-login-password-123" }
  let(:store) { workspace(name: "Synthetic merchant workspace") }
  let(:merchant) { store.users.create!(email: "merchant-#{SecureRandom.hex(5)}@example.test", password: password, admin: true) }

  def workspace(**attributes)
    Store.create!({ slug: "signin-#{SecureRandom.hex(5)}", name: "Synthetic other workspace", currency: "MAD" }.merge(attributes))
  end

  def login(user = merchant, **attributes)
    post "/admin/login", params: { email: user.email, password: password }.merge(attributes)
  end

  def alert_text
    Nokogiri::HTML(response.body).at_css('[role="alert"]')&.text&.strip
  end

  before { host! Store.base_domain }

  [true, false].each do |enabled|
    it "opens the approved merchant's apex dashboard with storefront_enabled=#{enabled}" do
      store.update!(storefront_enabled: enabled)
      foreign = workspace(name: "Foreign workspace must stay private")
      login
      expect(response).to redirect_to(admin_root_path)
      follow_redirect!
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(store.name)
      expect(response.body).not_to include(foreign.name)
      get "/en"
      expect(response).to have_http_status(:not_found)
    end
  end

  it "signs in on the localhost alias without redirecting to another host" do
    host! "localhost"
    login
    expect(response).to redirect_to("http://localhost/admin")
    follow_redirect!
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(store.name)
    expect(response.headers["Set-Cookie"].to_s).not_to include("domain=.#{Store.base_domain}")
  end

  it "normalizes merchant email on the shared sign-in form" do
    login(email: "  #{merchant.email.upcase}  ")
    expect(response).to redirect_to(admin_root_path)
    follow_redirect!
    expect(response).to have_http_status(:ok)
  end

  it "does not let submitted store IDs or slugs change an authenticated apex workspace" do
    foreign = workspace
    login
    expect(response).to redirect_to(admin_root_path)
    get "/admin", params: { store_id: foreign.id, workspace: foreign.slug }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(store.name)
  end

  it "cannot use a merchant cookie to access another tenant host" do
    login
    expect(response).to redirect_to(admin_root_path)
    foreign = workspace
    host! "#{foreign.slug}.#{Store.base_domain}"
    get "/admin"
    expect(response).to redirect_to(admin_login_path)
    expect(response.body).not_to include(store.name)
  end

  it "denies platform administration to an apex merchant" do
    login
    expect(response).to redirect_to(admin_root_path)
    get "/admin/platform"
    expect(response).to redirect_to(admin_root_path)
    follow_redirect!
    expect(response).to have_http_status(:ok)
  end

  it "removes merchant authentication and apex workspace context on logout" do
    login
    expect(response).to redirect_to(admin_root_path)
    delete "/admin/logout"
    expect(response).to redirect_to(admin_login_path)
    get "/admin"
    expect(response).to redirect_to(admin_login_path)
    get "/admin/login"
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include(store.name)
  end

  it "returns the same generic error for a wrong password and an unknown account" do
    login(password: "incorrect-synthetic-password")
    expect(response).to have_http_status(:unprocessable_entity)
    wrong_password_alert = alert_text
    expect(wrong_password_alert).to be_present
    login(email: "missing-#{SecureRandom.hex(5)}@example.test")
    expect(response).to have_http_status(:unprocessable_entity)
    expect(alert_text).to eq(wrong_password_alert)
    get "/admin"
    expect(response).to redirect_to(admin_login_path)
  end

  context "when the email belongs to two workspaces" do
    let!(:other_store) { workspace }
    let!(:other_merchant) { other_store.users.create!(email: merchant.email, password: "different-synthetic-password", admin: true) }

    it "rejects ambiguous sign-in without choosing an arbitrary account" do
      login
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).not_to include(store.name, other_store.name)
      get "/admin"
      expect(response).to redirect_to(admin_login_path)
    end

    it "allows explicit workspace selection with that workspace's credentials" do
      login(workspace: store.slug)
      expect(response).to redirect_to(admin_root_path)
      follow_redirect!
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(store.name)
    end

    it "does not authenticate a workspace using the other workspace's password" do
      login(workspace: other_store.slug)
      expect(response).to have_http_status(:unprocessable_entity)
      get "/admin"
      expect(response).to redirect_to(admin_login_path)
    end
  end

  it "rejects an explicit workspace without a matching membership" do
    foreign = workspace
    login(workspace: foreign.slug)
    expect(response).to have_http_status(:unprocessable_entity)
    get "/admin"
    expect(response).to redirect_to(admin_login_path)
  end

  it "keeps tenant-host sign-in scoped to the host despite a workspace parameter" do
    foreign = workspace
    host! "#{foreign.slug}.#{Store.base_domain}"
    login(workspace: store.slug)
    expect(response).to have_http_status(:unprocessable_entity)
    get "/admin"
    expect(response).to redirect_to(admin_login_path)
  end

  it "continues to allow merchant sign-in on their own tenant host" do
    host! "#{store.slug}.#{Store.base_domain}"
    login
    expect(response).to redirect_to(admin_root_path)
    follow_redirect!
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(store.name)
  end

  it "keeps platform-only super administrators on platform administration" do
    admin = User.create!(email: "platform-signin-#{SecureRandom.hex(5)}@example.test", password: password, admin: true, super_admin: true)
    login(admin)
    expect(response).to redirect_to(admin_platform_path)
    follow_redirect!
    expect(response).to have_http_status(:ok)
  end

  it "does not grant an admin session to a non-admin account" do
    merchant.update!(admin: false)
    login
    expect(response).to have_http_status(:unprocessable_entity)
    get "/admin"
    expect(response).to redirect_to(admin_login_path)
  end

  it "does not authenticate a pending access request before approval provisions an account" do
    pending = AccessRequest.create!(store_name: "Pending synthetic merchant", email: "pending-#{SecureRandom.hex(5)}@example.test", locale: "fr", storefront_enabled: false)
    expect do
      post "/admin/login", params: { email: pending.email, password: password }
    end.not_to change(User, :count)
    expect(response).to have_http_status(:unprocessable_entity)
    get "/admin"
    expect(response).to redirect_to(admin_login_path)
    expect(pending.reload).to be_pending
    expect(pending.store_id).to be_nil
  end

  it "preserves an existing same-host OAuth return destination across session renewal" do
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
    host! "#{store.slug}.#{Store.base_domain}"
    client = OauthClient.register!(name: "Synthetic login client", redirect_uris: ["https://synthetic.example.test/oauth/callback"])
    get "/oauth/authorize", params: { client_id: client.client_id, redirect_uri: client.redirect_uris.first, code_challenge: "synthetic-pkce-challenge", code_challenge_method: "S256" }
    expect(URI.parse(response.location).path).to eq(admin_login_path)
    login
    expect(response).to have_http_status(:redirect)
    expect(URI.parse(response.location).path).to eq("/oauth/authorize")
    follow_redirect!
    expect(response).to have_http_status(:ok)
  end

  it "ignores a submitted external return destination" do
    login(return_to: "https://synthetic.example.test/untrusted")
    expect(response).to redirect_to(admin_root_path)
  end
end


