# frozen_string_literal: true

require "rails_helper"
require "nokogiri"

RSpec.describe "Platform home auth navbar", type: :request do
  let(:suffix) { SecureRandom.hex(4) }
  let(:password) { "Synthetic-home-#{suffix}-pw" }

  def document
    Nokogiri::HTML(response.body)
  end

  def sign_in(user)
    host! Store.base_domain
    post "/admin/login", params: { email: user.email, password: password }
  end

  before { host! Store.base_domain }

  it "shows sign-in and sign-up for guests" do
    get "/", params: { locale: "en" }
    expect(response).to have_http_status(:ok)
    expect(document.at_css('[data-platform-auth="guest"]')).to be_present
    expect(document.at_css('[data-platform-auth="signed-in"]')).to be_nil
    expect(document.at_css("a.platform-login-nav")["href"]).to include("/admin/login")
    expect(document.css("a.platform-header-button").map { |a| a["href"] }.join).to include("/signup")
    expect(response.body).not_to match(/translation missing/i)
  end

  it "shows a dashboard entry for a signed-in merchant and hides guest CTAs" do
    store = Store.create!(name: "Home #{suffix}", slug: "home-#{suffix}", currency: "MAD", storefront_enabled: false)
    owner = store.users.create!(email: "owner-#{suffix}@example.test", password: password, admin: true)
    sign_in(owner)

    get "/", params: { locale: "en" }
    expect(response).to have_http_status(:ok)
    button = document.at_css('[data-platform-auth="signed-in"]')
    expect(button).to be_present
    expect(button["href"]).to eq("/admin")
    expect(button.text.squish).to include("Dashboard")
    expect(document.at_css('[data-platform-auth="guest"]')).to be_nil
    expect(document.css("a.platform-header-button").map { |a| a["href"] }.join).not_to include("/signup")
    expect(response.body).not_to match(/translation missing/i)
  end

  it "sends a signed-in confirmation agent to their confirmation home" do
    store = Store.create!(name: "Agent home #{suffix}", slug: "agent-home-#{suffix}", currency: "MAD", storefront_enabled: false)
    agent = store.users.create!(email: "agent-#{suffix}@example.test", password: password, admin: false, confirmation_role: "agent")
    sign_in(agent)

    get "/", params: { locale: "fr" }
    expect(response).to have_http_status(:ok)
    button = document.at_css('[data-platform-auth="signed-in"]')
    expect(button["href"]).to eq(home_admin_confirmations_path)
    expect(response.body).not_to match(/translation missing/i)
  end

  it "sends a signed-in platform admin to platform administration" do
    admin = User.create!(email: "plat-#{suffix}@example.test", password: password, admin: true, super_admin: true)
    sign_in(admin)

    get "/", params: { locale: "en" }
    expect(response).to have_http_status(:ok)
    expect(document.at_css('[data-platform-auth="signed-in"]')["href"]).to eq(admin_platform_path)
  end

  it "keeps a tenant-host sign-in visible on the shared apex home" do
    store = Store.create!(name: "Tenant #{suffix}", slug: "tenant-#{suffix}", currency: "MAD", storefront_enabled: false)
    owner = store.users.create!(email: "tenant-#{suffix}@example.test", password: password, admin: true)
    host! "#{store.slug}.#{Store.base_domain}"
    post "/admin/login", params: { email: owner.email, password: password }
    expect(response).to redirect_to(admin_root_path)

    host! Store.base_domain
    get "/", params: { locale: "en" }
    expect(document.at_css('[data-platform-auth="signed-in"]')).to be_present
    expect(document.at_css('[data-platform-auth="guest"]')).to be_nil
  end
end
