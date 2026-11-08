# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Ameex settings page", type: :request do
  let(:suffix) { SecureRandom.hex(5) }
  let(:password) { "Synthetic-ameex-#{suffix}-password" }
  let(:store) { Store.create!(name: "Synthetic #{suffix}", slug: "ameex-settings-#{suffix}", currency: "MAD", storefront_enabled: false) }
  let(:owner) { store.users.create!(email: "owner-#{suffix}@example.test", password: password, admin: true) }
  let!(:account) do
    store.delivery_accounts.create!(
      name: "Ameex main",
      provider: "ameex",
      credentials: { "api_key" => "synthetic-c-api-id", "api_secret" => "synthetic-ameex-key" },
      connected_at: Time.current,
      allow_open: true,
      pickup_city: "Casablanca",
      webhook_token: "ameex-token-#{suffix}"
    )
  end

  def sign_in
    host! "#{store.slug}.#{Store.base_domain}"
    post "/admin/login", params: { email: owner.email, password: password }
  end

  before { sign_in }

  it "shows connection status and options without embedding credentials" do
    get admin_ameex_settings_path
    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    expect(document.at_css("#ameex-settings")).to be_present
    expect(document.at_css("[name='delivery_account[allow_open]']")).to be_present
    expect(response.body).to include(account.webhook_url)
    expect(response.body).not_to include("synthetic-ameex-key", "translation_missing")
  end

  it "links from integrations to the dedicated settings page" do
    get seller_integrations_path
    expect(response).to have_http_status(:ok)
    card = Nokogiri::HTML(response.body).at_css("[data-carrier=ameex]")
    expect(card.text).to include("Connectée")
    expect(card.at_css("a[href='#{admin_ameex_settings_path}']")).to be_present
  end

  it "saves parcel options on the authorized workspace account" do
    patch admin_ameex_settings_path, params: {
      delivery_account: { allow_open: "0", pickup_city: "Fès", delivery_fee: "18", return_fee: "8", is_active: "1" }
    }
    expect(response).to redirect_to(admin_ameex_settings_path)
    expect(account.reload).to have_attributes(allow_open: false, pickup_city: "Fès", delivery_fee: 18, return_fee: 8)
  end

  it "queues an explicit city refresh for the connected workspace" do
    expect { post refresh_cities_admin_ameex_settings_path }.to have_enqueued_job(AmeexCitiesRefreshJob).with(store.id)
    expect(response).to redirect_to(admin_ameex_settings_path)
  end
end
