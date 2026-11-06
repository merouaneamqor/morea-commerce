# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Seller Liquid Glass app shell", type: :request do
  let(:password) { "synthetic-glass-password-123" }
  let(:store) { Store.create!(slug: "glass-#{SecureRandom.hex(5)}", name: "Glass Boutique", currency: "MAD", storefront_enabled: false, plan: "starter") }
  let(:owner) { store.users.create!(email: "glass-#{SecureRandom.hex(5)}@example.test", password: password, admin: true) }

  def document
    Nokogiri::HTML(response.body)
  end

  before do
    host! "#{store.slug}.#{Store.base_domain}"
    post "/admin/login", params: { email: owner.email, password: password }
  end

  it "renders the liquid glass seller shell with install metadata, no zoom, and glass chrome" do
    get "/dashboard"
    expect(response).to have_http_status(:ok)
    page = document
    expect(page.at_css("link[href*='liquid_glass']")).to be_present
    expect(page.at_css("meta[name=viewport]")["content"]).to include("maximum-scale=1", "user-scalable=no", "viewport-fit=cover")
    expect(page.at_css('link[rel="manifest"]')["href"]).to eq("/admin/manifest.webmanifest")
    expect(page.at_css('meta[name="apple-mobile-web-app-capable"]')["content"]).to eq("yes")
    expect(page.at_css("[data-seller-shell].lg-shell")).to be_present
    expect(page.at_css("aside nav.lg-nav")).to be_present
    expect(page.at_css(".lg-chrome")).to be_present
    expect(page.at_css("[data-admin-pwa].lg-panel")).to be_present
    expect(page.at_css("[data-seller-drawer].lg-scrim")).to be_present
    expect(page.at_css("[data-seller-bottom-nav].lg-bottom-nav")).to be_present
    expect(page.css("[data-seller-open]").size).to be >= 2
    expect(page.at_css("[data-seller-bottom-nav] a[href='/commandes']")).to be_present
  end

  it "exposes the order alerts toggle when VAPID is configured" do
    allow(Rails.configuration.x).to receive(:web_push).and_return(
      public_key: "BOsynthetic", private_key: "secret", subject: "mailto:support@example.test"
    )
    get "/dashboard"
    expect(document.at_css("[data-controller='order-alerts']")).to be_present
    expect(document.at_css("[data-order-alerts-target='toggle']")).to be_present
  end
end
