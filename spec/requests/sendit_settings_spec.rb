# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Sendit settings page", type: :request do
  let(:suffix) { SecureRandom.hex(5) }
  let(:password) { "Synthetic-settings-#{suffix}-password" }
  let(:store) { Store.create!(name: "Synthetic #{suffix}", slug: "sendit-settings-#{suffix}", currency: "MAD", storefront_enabled: false) }
  let(:owner) { store.users.create!(email: "owner-#{suffix}@example.test", password: password, admin: true) }

  def sign_in(user = owner)
    host! "#{store.slug}.#{Store.base_domain}"
    post "/admin/login", params: { email: user.email, password: password }
    expect(response).to have_http_status(:redirect)
  end

  def settings_form
    Nokogiri::HTML(response.body).css("#sendit-settings form").find { |form| form.at_css("input[name=\"_method\"][value=\"patch\"]") }
  end

  def save_settings(fields)
    patch admin_sendit_settings_path, params: { store: fields }
  end

  before { sign_in }

  it "offers the runtime controls in all three languages without exposing saved secrets" do
    store.update!(sendit_webhook_secret: "synthetic-webhook-secret", sendit_pickup_district_id: 42)
    %w[fr en ar].each do |locale|
      get admin_sendit_settings_path(locale: locale)
      expect(response).to have_http_status(:ok)
      expect(settings_form).to be_present
      %w[sendit_pickup_district_id sendit_allow_open sendit_allow_try sendit_webhook_secret shipping_dh free_shipping_threshold_dh].each do |field|
        expect(settings_form.at_css("[name='store[#{field}]']")).to be_present, "missing #{field} in #{locale}"
      end
      expect(settings_form.at_css("[name='store[sendit_webhook_secret]']")["value"]).to be_blank
      expect(settings_form.at_css("[name='store[sendit_pickup_district_id]'] option[selected]")["value"]).to eq("42")
      expect(response.body).not_to include("synthetic-webhook-secret", "translation_missing")
      expect(settings_form.css("[name='store[sendit_public_key]'], [name='store[sendit_secret_key]']")).to be_empty
      expect(Nokogiri::HTML(response.body).at_css("html")["dir"]).to eq("rtl") if locale == "ar"
    end
  end

  it "keeps Sendit controls off the integrations page and links to the settings page" do
    store.delivery_accounts.create!(name: "Synthetic Sendit", provider: "sendit",
      credentials: { "api_key" => "synthetic-public", "api_secret" => "synthetic-secret" }, connected_at: Time.current)
    get seller_integrations_path
    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    expect(document.at_css("#sendit-settings")).to be_nil
    expect(document.at_css("a[href='#{admin_sendit_settings_path}']")).to be_present
  end

  it "moves Sendit controls out of the general settings page" do
    get edit_admin_store_path
    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    %w[sendit_public_key sendit_secret_key sendit_webhook_secret sendit_pickup_district_id sendit_allow_open sendit_allow_try shipping_dh free_shipping_threshold_dh].each do |field|
      expect(document.css("[name='store[#{field}]']")).to be_empty
    end
    expect(document.at_css("a[href='#{admin_sendit_settings_path}']")).to be_present
  end

  it "saves pickup, parcel permissions, webhook secret and MAD amounts on the current workspace" do
    save_settings(sendit_pickup_district_id: "17", sendit_allow_open: "1", sendit_allow_try: "0",
      sendit_webhook_secret: "synthetic-replacement", shipping_dh: "35", free_shipping_threshold_dh: "450")
    expect(response).to have_http_status(:see_other)
    expect(response).to redirect_to(admin_sendit_settings_path)
    expect(store.reload).to have_attributes(sendit_pickup_district_id: 17, sendit_allow_open: true, sendit_allow_try: false,
      sendit_webhook_secret: "synthetic-replacement", shipping_cents: 3500, free_shipping_threshold_cents: 45_000)
  end

  it "preserves blank secrets and credentials while allowing the free shipping threshold to be removed" do
    store.update!(sendit_webhook_secret: "synthetic-existing", sendit_public_key: "legacy-public", sendit_secret_key: "legacy-secret",
      free_shipping_threshold_cents: 50_000)
    save_settings(sendit_webhook_secret: "", free_shipping_threshold_dh: "", sendit_public_key: "injected-public", sendit_secret_key: "injected-secret")
    expect(response).to have_http_status(:see_other)
    expect(store.reload).to have_attributes(sendit_webhook_secret: "synthetic-existing", free_shipping_threshold_cents: nil,
      sendit_public_key: "legacy-public", sendit_secret_key: "legacy-secret")
  end

  it "cannot choose another workspace by submitting its ID" do
    other = Store.create!(name: "Foreign #{suffix}", slug: "foreign-#{suffix}", currency: "MAD", shipping_cents: 9900)
    save_settings(id: other.id, store_id: other.id, shipping_dh: "20")
    expect(response).to have_http_status(:see_other)
    expect(store.reload.shipping_cents).to eq(2000)
    expect(other.reload.shipping_cents).to eq(9900)
  end

  it "does not authorize this store's session on another tenant host" do
    other = Store.create!(name: "Foreign #{suffix}", slug: "foreign-#{suffix}", currency: "MAD", shipping_cents: 9900)
    host! "#{other.slug}.#{Store.base_domain}"
    save_settings(shipping_dh: "20")
    expect(response).to redirect_to(admin_login_path)
    expect(other.reload.shipping_cents).to eq(9900)
  end

  it "denies unauthenticated writes" do
    delete "/admin/logout"
    original = store.reload.shipping_cents
    save_settings(shipping_dh: "99")
    expect(response).to redirect_to(admin_login_path)
    expect(store.reload.shipping_cents).to eq(original)
  end

  it "keeps confirmation agents out of integration settings" do
    delete "/admin/logout"
    agent = store.users.create!(name: "Synthetic agent", email: "agent-#{suffix}@example.test", password: password, confirmation_role: "agent", admin: false)
    sign_in(agent)
    original = store.reload.shipping_cents
    save_settings(shipping_dh: "99")
    expect(response).to redirect_to(home_admin_confirmations_path)
    expect(store.reload.shipping_cents).to eq(original)
    get admin_sendit_settings_path
    expect(response).to redirect_to(home_admin_confirmations_path)
  end

  it "renders connected settings with a cold cache without contacting Sendit" do
    store.delivery_accounts.create!(name: "Synthetic Sendit", provider: "sendit", credentials: { "api_key" => "synthetic-public", "api_secret" => "synthetic-secret" })
    allow(Rails.cache).to receive(:read).and_call_original
    allow(Rails.cache).to receive(:read).with(Sendit::Districts.cache_key(store)).and_return(nil)
    allow(Rails.cache).to receive(:read).with("#{Sendit::Districts.cache_key(store)}:pickup").and_return(nil)
    expect(Sendit::Client).not_to receive(:new)
    expect(Sendit::Client).not_to receive(:verify!)
    get admin_sendit_settings_path
    expect(response).to have_http_status(:ok)
    expect(settings_form).to be_present
  end

  it "shows the managed account's authenticated webhook instead of legacy secret controls" do
    store.update!(sendit_webhook_secret: "synthetic-legacy-secret")
    account = store.delivery_accounts.create!(name: "Managed Sendit", provider: "sendit",
      credentials: { "api_key" => "synthetic-public", "api_secret" => "synthetic-secret" }, webhook_token: "synthetic-token-#{suffix}")
    get admin_sendit_settings_path
    expect(response).to have_http_status(:ok)
    expect(Nokogiri::HTML(response.body).at_css("#sendit-settings").text).to include(account.webhook_url)
    expect(settings_form.at_css("[name='store[sendit_webhook_secret]']")).to be_nil
    expect(response.body).not_to include("synthetic-legacy-secret", "synthetic-secret")
  end

  it "shows cached pickup cities and delivery rates without making provider calls" do
    store.update!(sendit_pickup_district_id: 17, sendit_public_key: "synthetic-public", sendit_secret_key: "synthetic-secret")
    allow(Rails.cache).to receive(:read).and_call_original
    allow(Rails.cache).to receive(:read).with(Sendit::Districts.cache_key(store)).and_return([ { id: 1, ville: "Synthetic city", name: "Synthetic district", price: "35" } ])
    allow(Rails.cache).to receive(:read).with("#{Sendit::Districts.cache_key(store)}:pickup").and_return([ { id: 17, name: "Synthetic pickup" } ])
    expect(Sendit::Client).not_to receive(:new)
    get admin_sendit_settings_path
    expect(response).to have_http_status(:ok)
    expect(settings_form.at_css("option[value='17']").text).to include("Synthetic pickup")
    expect(response.body).to include("Synthetic city")
  end

  describe "legacy disconnection" do
    before { store.update!(sendit_public_key: "legacy-public", sendit_secret_key: "legacy-secret", sendit_webhook_secret: "legacy-webhook") }

    it "removes legacy credentials even when old inactive account rows remain" do
      old = store.delivery_accounts.create!(name: "Old Sendit", provider: "sendit", is_active: false,
        credentials: { "api_key" => "old-public", "api_secret" => "old-secret" })
      delete admin_sendit_settings_path
      expect(response).to have_http_status(:see_other)
      expect(store.reload.sendit_configured?).to be(false)
      expect(store).to have_attributes(sendit_webhook_secret: nil)
      expect(old.reload).to be_present
    end

    it "does not disconnect a managed account through the legacy action" do
      account = store.delivery_accounts.create!(name: "Current Sendit", provider: "sendit",
        credentials: { "api_key" => "current-public", "api_secret" => "current-secret" })
      delete admin_sendit_settings_path
      expect(response).to have_http_status(:see_other)
      expect(account.reload.credentials).to include("api_secret" => "current-secret")
      expect(store.reload[:sendit_secret_key]).to eq("legacy-secret")
    end
  end

  describe "city refresh" do
    it "queues an explicit refresh for the current configured workspace" do
      store.update!(sendit_public_key: "legacy-public", sendit_secret_key: "legacy-secret")
      expect(Sendit::Client).not_to receive(:new)
      expect { post refresh_cities_admin_sendit_settings_path }.to have_enqueued_job(SenditCitiesRefreshJob).with(store.id)
      expect(response).to have_http_status(:see_other)
    end

    it "does not queue a refresh without credentials" do
      expect { post refresh_cities_admin_sendit_settings_path }.not_to have_enqueued_job(SenditCitiesRefreshJob)
      expect(response).to have_http_status(:see_other)
    end
  end
end
