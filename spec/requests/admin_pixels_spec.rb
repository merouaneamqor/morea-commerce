# frozen_string_literal: true

require "rails_helper"
require "nokogiri"

RSpec.describe "Admin pixels settings", type: :request do
  let(:password) { "synthetic-pixels-password-123" }
  let(:store) { Store.create!(slug: "pix-#{SecureRandom.hex(5)}", name: "Synthetic Pixels", currency: "MAD", storefront_enabled: true) }
  let(:staff) { store.users.create!(email: "pix-#{SecureRandom.hex(5)}@example.test", password: password, admin: true) }
  let(:other) { Store.create!(slug: "pix-oth-#{SecureRandom.hex(5)}", name: "Other workspace", currency: "MAD", storefront_enabled: true) }

  def tenant_host = "#{store.slug}.#{Store.base_domain}"

  def sign_in(user = staff)
    host! tenant_host
    post "/admin/login", params: { email: user.email, password: password }
    expect(response).to have_http_status(:redirect)
  end

  def document
    Nokogiri::HTML(response.body)
  end

  it "requires a signed-in store operator" do
    host! tenant_host
    get "/pixels"
    expect(response).to redirect_to("/admin/login")
    patch "/admin/pixels", params: { store: { meta_pixel_id: "123456789012345" } }
    expect(response).to redirect_to("/admin/login")
  end

  it "opens from the seller Pixels menu and highlights that entry" do
    sign_in
    get "/pixels"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t("pixels.meta.title"))
    expect(response.body).to include(I18n.t("pixels.tiktok.title"))
    expect(response.body).to include(I18n.t("pixels.analytics.title"))
    expect(document.at_css("[data-pixel=meta]")).to be_present
    expect(document.at_css("[data-pixel=tiktok]")).to be_present
    expect(document.at_css("[data-pixel=analytics]")).to be_present
    active = document.css("aside nav ul a").find { |link| link["href"] == "/pixels" }
    expect(active["class"]).to include("lg-nav__active", "font-semibold")
  end

  it "saves Meta, TikTok and Google Analytics ids on the current store" do
    sign_in
    patch "/admin/pixels", params: {
      store: {
        meta_pixel_id: "123456789012345",
        tiktok_pixel_id: "CABCDEFGHIJKLMNOP",
        google_analytics_id: "g-abc123xyz"
      }
    }
    expect(response).to redirect_to("/pixels")
    expect(store.reload).to have_attributes(
      meta_pixel_id: "123456789012345",
      tiktok_pixel_id: "CABCDEFGHIJKLMNOP",
      google_analytics_id: "G-ABC123XYZ"
    )
    expect(other.reload.meta_pixel_id).to be_blank
    expect(other.google_analytics_id).to be_blank
  end

  it "rejects invalid Analytics ids and keeps previous values" do
    store.update!(meta_pixel_id: "123456789012345", google_analytics_id: "G-KEEPME01")
    sign_in
    patch "/admin/pixels", params: {
      store: {
        meta_pixel_id: "123456789012345",
        tiktok_pixel_id: "",
        google_analytics_id: "UA-12345-1"
      }
    }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("must look like G-XXXXXXXXXX")
    expect(store.reload.google_analytics_id).to eq("G-KEEPME01")
  end

  it "clears ids when fields are blank" do
    store.update!(meta_pixel_id: "123456789012345", tiktok_pixel_id: "CABCDEFGHIJKLMNOP", google_analytics_id: "G-CLEARME01")
    sign_in
    patch "/admin/pixels", params: { store: { meta_pixel_id: "", tiktok_pixel_id: "", google_analytics_id: "" } }
    expect(response).to redirect_to("/pixels")
    expect(store.reload).to have_attributes(meta_pixel_id: nil, tiktok_pixel_id: nil, google_analytics_id: nil)
  end

  it "loads Google Analytics on the storefront only after measurement consent" do
    store.update!(google_analytics_id: "G-STOREFRONT1")
    host! tenant_host
    get "/en"
    expect(response.body).not_to include("googletagmanager.com/gtag")

    post tracking_consent_path, params: { choice: "granted" }, as: :json
    get "/en"
    expect(response.body).to include("googletagmanager.com/gtag/js?id=G-STOREFRONT1")
    expect(response.body).to include('gtag(\'config\', "G-STOREFRONT1"')
  end
end
