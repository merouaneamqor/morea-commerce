# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Ozon Express settings page", type: :request do
  let(:suffix) { SecureRandom.hex(5) }
  let(:password) { "Synthetic-ozon-#{suffix}-password" }
  let(:store) { Store.create!(name: "Synthetic #{suffix}", slug: "ozon-settings-#{suffix}", currency: "MAD", storefront_enabled: false) }
  let(:owner) { store.users.create!(email: "owner-#{suffix}@example.test", password: password, admin: true) }
  let!(:account) do
    store.delivery_accounts.create!(
      name: "Ozon main",
      provider: "ozon",
      credentials: { "api_key" => "synthetic-customer", "api_secret" => "synthetic-ozon-key" },
      connected_at: Time.current,
      allow_open: true,
      pickup_city: "Casablanca",
      delivery_fee: 25,
      return_fee: 10,
      webhook_token: "ozon-token-#{suffix}"
    )
  end

  def sign_in
    host! "#{store.slug}.#{Store.base_domain}"
    post "/admin/login", params: { email: owner.email, password: password }
  end

  before { sign_in }

  it "shows connection status and options without embedding credentials" do
    get admin_ozon_settings_path
    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    expect(document.at_css("#ozon-settings")).to be_present
    expect(document.at_css("[name='delivery_account[allow_open]']")).to be_present
    expect(response.body).to include(account.webhook_url)
    expect(response.body).not_to include("synthetic-ozon-key", "translation_missing")
  end

  it "links from integrations to the dedicated settings page" do
    get seller_integrations_path
    expect(response).to have_http_status(:ok)
    card = Nokogiri::HTML(response.body).at_css("[data-carrier=ozon]")
    expect(card.text).to include("Connectée")
    expect(card.at_css("a[href='#{admin_ozon_settings_path}']")).to be_present
  end

  it "saves parcel options on the authorized workspace account" do
    patch admin_ozon_settings_path, params: {
      delivery_account: { allow_open: "0", pickup_city: "Rabat", delivery_fee: "30", return_fee: "12", is_active: "1" }
    }
    expect(response).to redirect_to(admin_ozon_settings_path)
    expect(account.reload).to have_attributes(allow_open: false, pickup_city: "Rabat", delivery_fee: 30, return_fee: 12, is_active: true)
  end

  it "cannot update another workspace's account by id" do
    other = Store.create!(name: "Foreign #{suffix}", slug: "foreign-ozon-#{suffix}", currency: "MAD", storefront_enabled: false)
    foreign = other.delivery_accounts.create!(
      name: "Foreign Ozon",
      provider: "ozon",
      credentials: { "api_key" => "foreign", "api_secret" => "foreign-secret" },
      connected_at: Time.current,
      allow_open: true
    )
    patch admin_ozon_settings_path, params: {
      delivery_account: { id: foreign.id, allow_open: "0", pickup_city: "Injected" }
    }
    expect(response).to redirect_to(admin_ozon_settings_path)
    expect(account.reload.allow_open).to be(false)
    expect(foreign.reload).to have_attributes(allow_open: true, pickup_city: nil)
  end

  it "queues an explicit city refresh for the connected workspace" do
    expect { post refresh_cities_admin_ozon_settings_path }.to have_enqueued_job(OzonCitiesRefreshJob).with(store.id)
    expect(response).to redirect_to(admin_ozon_settings_path)
  end
end
