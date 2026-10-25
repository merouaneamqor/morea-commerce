require "rails_helper"
require "nokogiri"

RSpec.describe "Admin PWA", type: :request do
  let(:password) { "synthetic-pwa-password-123" }
  let!(:store) { Store.create!(slug: "pwa-#{SecureRandom.hex(5)}", name: "Synthetic PWA workspace", currency: "MAD", storefront_enabled: false) }

  before { host! Store.base_domain }

  def document
    Nokogiri::HTML(response.body)
  end

  it "serves public, workspace-independent installation metadata on apex and tenant hosts" do
    [ Store.base_domain, "#{store.slug}.#{Store.base_domain}" ].each do |hostname|
      host! hostname
      get "/admin/manifest.webmanifest"
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/manifest+json")
      manifest = JSON.parse(response.body)
      expect(manifest).to include("name" => Store.platform_name, "display" => "standalone", "scope" => "/admin", "start_url" => "/admin", "id" => "/admin")
      expect(manifest.fetch("icons").map { |icon| icon.fetch("sizes") }).to contain_exactly("192x192", "512x512")
      expect(response.body).not_to include(store.name, store.slug)
      get "/admin/service-worker.js"
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/javascript")
      expect(response.headers["Service-Worker-Allowed"]).to eq("/admin")
      expect(response.headers["Cache-Control"]).to include("no-cache")
    end
  end

  it "does not show an install prompt before sign-in or on the public landing page" do
    [ "/admin/login", "/" ].each do |path|
      get path
      expect(response).to have_http_status(:ok)
      expect(document.at_css("[data-admin-pwa]")).to be_nil
      expect(document.at_css('link[rel="manifest"]')).to be_nil
    end
    get "/admin"
    expect(response).to redirect_to(admin_login_path)
  end

  %w[fr en ar].each do |locale|
    it "offers installation after platform sign-in in #{locale}" do
      user = User.create!(email: "pwa-#{SecureRandom.hex(5)}@example.test", password: password, admin: true, super_admin: true)
      post "/admin/login", params: { email: user.email, password: password }
      get "/admin/platform", params: { locale: locale }
      expect(response).to have_http_status(:ok)
      expect(document.at_css("[data-admin-pwa]")).to be_present
      expect(document.at_css('link[rel="manifest"]')["href"]).to eq("/admin/manifest.webmanifest")
      expect(document.at_css('meta[name="apple-mobile-web-app-capable"]')["content"]).to eq("yes")
      expect(response.body).not_to match(/translation missing|translation_missing/i)
    end
  end

  it "offers installation to authenticated merchants in unpublished workspaces" do
    user = store.users.create!(email: "pwa-merchant-#{SecureRandom.hex(5)}@example.test", password: password, admin: true)
    post "/admin/login", params: { email: user.email, password: password }
    get "/admin"
    expect(response).to have_http_status(:ok)
    expect(document.at_css("[data-admin-pwa]")).to be_present
  end
end
