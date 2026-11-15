# frozen_string_literal: true

require "rails_helper"
require "nokogiri"

RSpec.describe "Black Friday storefront theme", type: :request do
  let(:suffix) { SecureRandom.hex(5) }
  let(:password) { "Synthetic-bf-#{suffix}-password" }
  let(:store) do
    Store.create!(
      name: "Boutique #{suffix}",
      slug: "bf-#{suffix}",
      currency: "MAD",
      storefront_enabled: true,
      subscription_required: false
    )
  end
  let(:owner) { store.users.create!(email: "owner-#{suffix}@example.test", password: password, admin: true) }

  def sign_in
    host! "#{store.slug}.#{Store.base_domain}"
    post "/admin/login", params: { email: owner.email, password: password }
    expect(response).to have_http_status(:redirect)
  end

  def document
    Nokogiri::HTML(response.body)
  end

  it "defaults off and leaves the storefront without the theme class" do
    expect(store.black_friday_theme).to be(false)
    host! "#{store.slug}.#{Store.base_domain}"
    get "/en"
    expect(response).to have_http_status(:ok)
    body = document.at_css("body")
    expect(body["class"].to_s.split).not_to include("theme-black-friday")
    expect(response.body).not_to include("black_friday_theme")
  end

  it "shows the toggle on settings and persists activate / deactivate" do
    sign_in
    get edit_admin_store_path
    expect(response).to have_http_status(:ok)
    expect(document.at_css("#black-friday input[name='store[black_friday_theme]']")).to be_present
    expect(response.body).not_to include("translation_missing")

    patch admin_store_path, params: { store: { black_friday_theme: "1" } }
    expect(response).to redirect_to(edit_admin_store_path)
    expect(store.reload.black_friday_theme).to be(true)

    patch admin_store_path, params: { store: { black_friday_theme: "0" } }
    expect(response).to redirect_to(edit_admin_store_path)
    expect(store.reload.black_friday_theme).to be(false)
  end

  it "cannot enable the theme on another workspace by forged id" do
    other = Store.create!(name: "Other #{suffix}", slug: "other-bf-#{suffix}", currency: "MAD", storefront_enabled: true)
    sign_in
    patch admin_store_path, params: { store: { id: other.id, store_id: other.id, black_friday_theme: "1" } }
    expect(store.reload.black_friday_theme).to be(true)
    expect(other.reload.black_friday_theme).to be(false)
  end

  it "applies the theme class, banner and stylesheet when enabled" do
    store.update!(black_friday_theme: true)
    host! "#{store.slug}.#{Store.base_domain}"
    get "/en"
    expect(response).to have_http_status(:ok)
    body = document.at_css("body")
    expect(body["class"].to_s.split).to include("theme-black-friday", "has-announcement")
    expect(document.at_css(".announcement-bar").text).to include("Black Friday")
    expect(document.at_css('link[href*="black_friday_theme"]')).to be_present
    expect(document.at_css('meta[name="theme-color"]')["content"]).to eq("#0a0a0a")
  end

  it "prefers a custom announcement over the default Black Friday banner" do
    store.update!(black_friday_theme: true)
    store.translations.find_or_initialize_by(locale: "en").update!(announcement: "Flash sale ends tonight")
    host! "#{store.slug}.#{Store.base_domain}"
    get "/en"
    expect(document.at_css(".announcement-bar").text).to eq("Flash sale ends tonight")
  end
end
