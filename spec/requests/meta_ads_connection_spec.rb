# frozen_string_literal: true

require "rails_helper"
require "nokogiri"
require "support/meta_ads_helpers"

RSpec.describe "Meta Ads connection", type: :request do
  let(:password) { "synthetic-meta-password-123" }
  let(:store) { Store.create!(slug: "meta-req-#{SecureRandom.hex(5)}", name: "Synthetic Meta workspace", currency: "MAD", storefront_enabled: false) }
  let(:staff) { store.users.create!(email: "meta-#{SecureRandom.hex(5)}@example.test", password: password, admin: true) }
  let(:other_store) { Store.create!(slug: "meta-oth-#{SecureRandom.hex(5)}", name: "Other workspace", currency: "MAD", storefront_enabled: false) }
  let(:token) { "synthetic-meta-access-token" }
  let(:granted) { %w[ads_read business_management] }
  let(:accounts) do
    [ { id: "act_11", name: "Main", currency: "EUR", account_status: 1, timezone_name: "Europe/Paris" },
      { id: "act_22", name: "Second", currency: "USD", account_status: 1, timezone_name: "UTC" },
      { id: "act_33", name: "Unpaid", currency: "USD", account_status: 3, timezone_name: "UTC" } ]
  end
  let(:calls) { [] }
  let(:transport) do
    lambda do |uri, request|
      calls << [ request.method, uri.path ]
      case uri.path
      when %r{/oauth/access_token}
        URI.decode_www_form(request.body).to_h["grant_type"] == "fb_exchange_token" ? meta_reply(access_token: token, expires_in: 5_184_000) : meta_reply(access_token: "synthetic-short")
      when %r{/debug_token} then meta_reply(data: { is_valid: true, scopes: granted, user_id: "42", expires_at: 55.days.from_now.to_i })
      when %r{/me/adaccounts} then meta_reply(data: accounts)
      when %r{/me/permissions} then meta_reply(success: true)
      else raise "Unexpected #{uri}"
      end
    end
  end

  before do
    stub_meta_env
    allow(MetaAds::Client).to receive(:new).and_wrap_original { |original, **options| original.call(**options, transport: transport) }
    allow(MetaAdsSyncJob).to receive(:perform_later)
  end

  def tenant_host = "#{store.slug}.#{Store.base_domain}"

  def sign_in(user = staff)
    host! tenant_host
    post "/admin/login", params: { email: user.email, password: password }
    expect(response).to have_http_status(:redirect)
  end

  def start_authorization
    host! tenant_host
    post "/admin/meta-ads/connect"
    expect(response).to have_http_status(:see_other)
    expect(URI(response.location).host).to eq("www.facebook.com")
    Rack::Utils.parse_nested_query(URI(response.location).query).fetch("state")
  end

  # Meta sends the browser back to the one redirect URI, on the platform apex.
  def meta_callback(params)
    host! Store.base_domain
    get "/auth/meta/callback", params: params
  end

  def connect!
    sign_in
    meta_callback(code: "synthetic-code", state: start_authorization)
    host! tenant_host
  end

  it "requires a signed-in store operator and a current store" do
    host! tenant_host
    get "/admin/meta-ads"
    expect(response).to redirect_to("/admin/login")
    post "/admin/meta-ads/connect"
    expect(response).to redirect_to("/admin/login")
  end

  it "connects through the apex callback, lists accounts and never renders the token" do
    connect!
    expect(URI(response.location).host).to eq(tenant_host)
    expect(URI(response.location).path).to eq("/admin/meta-ads")
    connection = store.reload.meta_ads_connection
    expect(connection).to have_attributes(status: "active", granted_scopes: %w[ads_read business_management], meta_user_id: "42")
    expect(store.meta_ads_ad_accounts.pluck(:meta_ad_account_id)).to match_array(%w[act_11 act_22 act_33])

    get "/admin/meta-ads"
    expect(response.body).to include("act_11", "EUR", "Europe/Paris", "Connecté")
    expect(response.body).not_to include(token, connection.access_token_ciphertext, "synthetic-app-secret")
  end

  it "shows unsettled accounts as not selectable and refuses to link them" do
    connect!
    get "/admin/meta-ads"
    page = Nokogiri::HTML(response.body)
    expect(page.at_css("[data-ad-account=act_33] input[type=checkbox]")["disabled"]).to be_present
    expect(page.at_css("[data-ad-account=act_33]").text).to include(I18n.t("meta_ads.account_status.unsettled"), I18n.t("meta_ads.not_selectable"))
    expect(page.at_css("[data-ad-account=act_11] input[type=checkbox]")["disabled"]).to be_nil

    patch "/admin/meta-ads/accounts", params: { ad_account_ids: %w[act_33] }
    expect(flash[:alert]).to eq(I18n.t("meta_ads.errors.account_not_selectable"))
    expect(store.meta_ads_ad_accounts.selected.count).to eq(0)
  end

  it "links several accounts, starts their first sync and shows them as waiting" do
    connect!
    patch "/admin/meta-ads/accounts", params: { ad_account_ids: %w[act_11 act_22] }
    expect(response).to redirect_to("/admin/meta-ads")
    expect(store.meta_ads_ad_accounts.selected.count).to eq(2)
    expect(MetaAdsSyncJob).to have_received(:perform_later).twice
    follow_redirect!
    expect(response.body).to include(I18n.t("meta_ads.sync_status.pending"))
  end

  it "rejects a callback with a forged state without changing the connection" do
    sign_in
    start_authorization
    meta_callback(code: "synthetic-code", state: SecureRandom.hex(32))
    expect(response).to have_http_status(:bad_request)
    expect(response.body).to include(I18n.t("meta_ads.errors.invalid_state"))
    expect(store.reload.meta_ads_connection).to have_attributes(status: "disconnected", access_token: nil)
  end

  it "rejects a replayed state and a state started by someone else" do
    sign_in
    state = start_authorization
    meta_callback(code: "synthetic-code", state: state)
    expect(store.reload.meta_ads_connection.status).to eq("active")
    store.meta_ads_connection.disconnect!
    meta_callback(code: "synthetic-code", state: state)
    expect(response).to have_http_status(:bad_request)
    expect(store.reload.meta_ads_connection.status).to eq("disconnected")

    # Another browser (no session) presenting a valid state is refused too.
    sign_in
    state = start_authorization
    reset!
    meta_callback(code: "synthetic-code", state: state)
    expect(response).to have_http_status(:bad_request)
    expect(store.reload.meta_ads_connection.access_token).to be_nil
  end

  it "answers a cancelled or denied login with a clear message and stores nothing" do
    sign_in
    state = start_authorization
    meta_callback(error: "access_denied", error_reason: "user_denied", state: state)
    expect(URI(response.location).host).to eq(tenant_host)
    host! tenant_host
    follow_redirect!
    expect(response.body).to include(I18n.t("meta_ads.errors.authorization_denied"))
    expect(store.reload.meta_ads_connection).to have_attributes(status: "disconnected", access_token: nil)
    expect(calls).to be_empty
  end

  it "explains when ads_read was not granted" do
    sign_in
    state = start_authorization
    granted.replace(%w[public_profile])
    meta_callback(code: "synthetic-code", state: state)
    host! tenant_host
    follow_redirect!
    expect(response.body).to include(I18n.t("meta_ads.errors.missing_scopes"))
    expect(store.reload.meta_ads_connection.status).to eq("disconnected")
  end

  it "does not serve the callback on a store host" do
    sign_in
    host! tenant_host
    get "/auth/meta/callback", params: { code: "c", state: "s" }
    expect(response).to have_http_status(:not_found)
  end

  it "is explicit when Meta is not configured" do
    stub_meta_env("META_APP_ID" => nil)
    sign_in
    post "/admin/meta-ads/connect"
    expect(flash[:alert]).to eq(I18n.t("meta_ads.errors.config_missing"))
  end

  it "keeps the Connect buttons clickable when Meta is not configured, and explains what is missing" do
    stub_meta_env("META_LOGIN_CONFIG_ID" => nil)
    sign_in
    [ "/integrations", "/admin/meta-ads" ].each do |path|
      get path
      button = Nokogiri::HTML(response.body).at_css("form[action='/admin/meta-ads/connect'] button")
      expect(button["disabled"]).to be_nil, "#{path} button must not be disabled"
    end
    post "/admin/meta-ads/connect"
    expect(flash[:alert]).to include("META_LOGIN_CONFIG_ID")
  end

  it "never lets one store read, select or sync another store's accounts" do
    other_connection = MetaAds::Connection.create!(store: other_store, access_token: "synthetic-other-token")
    foreign = other_store.meta_ads_ad_accounts.create!(connection: other_connection, meta_ad_account_id: "act_77", name: "Foreign", currency: "EUR", timezone_name: "UTC", account_status: 1)
    connect!

    get "/admin/meta-ads"
    expect(response.body).not_to include("act_77", "Foreign")
    patch "/admin/meta-ads/accounts", params: { ad_account_ids: %w[act_77], id: foreign.id }
    expect(flash[:alert]).to eq(I18n.t("meta_ads.errors.unknown_account"))
    expect(foreign.reload.selected).to be(false)
  end

  it "marks the connection for reconnection when Meta reports an invalid token (190), keeps history and lets the merchant reconnect" do
    connect!
    patch "/admin/meta-ads/accounts", params: { ad_account_ids: %w[act_11] }
    revoked = ->(_uri, _request) { meta_reply({ error: { code: 190, message: "Token revoked" } }, status: 400) }
    allow(MetaAds::Client).to receive(:new).and_wrap_original { |original, **options| original.call(**options, transport: revoked) }

    post "/admin/meta-ads/refresh"
    expect(flash[:alert]).to eq(I18n.t("meta_ads.errors.reauthorization_required"))
    connection = store.reload.meta_ads_connection
    expect(connection).to have_attributes(status: "needs_reauthorization", access_token: nil, last_error_code: "invalid_token")
    expect(store.meta_ads_ad_accounts.count).to eq(3)
    expect(store.meta_ads_ad_accounts.find_by!(meta_ad_account_id: "act_11").sync_status).to eq("needs_reauthorization")

    get "/admin/meta-ads"
    expect(response.body).to include(I18n.t("meta_ads.reauthorize_note"), I18n.t("meta_ads.reconnect"))
    get "/integrations"
    expect(Nokogiri::HTML(response.body).at_css("[data-meta-notice=needs_reconnect]")).to be_present

    allow(MetaAds::Client).to receive(:new).and_wrap_original { |original, **options| original.call(**options, transport: transport) }
    meta_callback(code: "synthetic-code", state: start_authorization)
    expect(MetaAds::Connection.where(store: store).count).to eq(1)
    expect(store.reload.meta_ads_connection.status).to eq("active")
  end

  it "warns in the app 7 days before the token expires, with a reconnect button, and not earlier" do
    connect!
    get "/integrations"
    expect(Nokogiri::HTML(response.body).at_css("[data-meta-notice]")).to be_nil

    store.meta_ads_connection.update!(token_expires_at: 6.days.from_now)
    get "/integrations"
    notice = Nokogiri::HTML(response.body).at_css("[data-meta-notice=expires_soon]")
    expect(notice).to be_present
    expect(notice.at_css("form[action='/admin/meta-ads/connect'] button, form[action='/admin/meta-ads/connect'] input[type=submit]")).to be_present
    get "/dashboard"
    expect(Nokogiri::HTML(response.body).at_css("[data-meta-notice=expires_soon]")).to be_present
  end

  it "disconnects: revokes the permissions at Meta, deletes the token and keeps the synced data" do
    connect!
    patch "/admin/meta-ads/accounts", params: { ad_account_ids: %w[act_11] }
    delete "/admin/meta-ads/connection"
    expect(response).to redirect_to("/admin/meta-ads")
    expect(calls).to include([ "DELETE", "/#{MetaAds::Config.api_version}/me/permissions" ])
    expect(flash[:notice]).to eq(I18n.t("meta_ads.disconnected_revoked"))
    expect(store.reload.meta_ads_connection).to have_attributes(status: "disconnected", access_token: nil, access_token_ciphertext: nil)
    expect(store.meta_ads_ad_accounts.count).to eq(3)
    expect(store.meta_ads_ad_accounts.selected.count).to eq(0)
  end

  it "still disconnects when Meta cannot be reached" do
    connect!
    down = ->(_uri, _request) { meta_reply({}, status: 503) }
    allow(MetaAds::Client).to receive(:new).and_wrap_original { |original, **options| original.call(**options, transport: down) }
    delete "/admin/meta-ads/connection"
    expect(flash[:notice]).to eq(I18n.t("meta_ads.disconnected_notice"))
    expect(store.reload.meta_ads_connection).to have_attributes(status: "disconnected", access_token: nil)
  end

  describe "Integrations page" do
    it "offers Connect Meta, then shows Meta as connected with a manage link" do
      sign_in
      get "/integrations"
      card = Nokogiri::HTML(response.body).at_css("[data-meta-card=disconnected]")
      expect(card.at_css("form[action='/admin/meta-ads/connect']")).to be_present
      expect(card.text).to include(I18n.t("meta_ads.connect"))

      meta_callback(code: "synthetic-code", state: start_authorization)
      host! tenant_host
      get "/integrations"
      card = Nokogiri::HTML(response.body).at_css("[data-meta-card=active]")
      expect(card.text).to include("Connectée", I18n.t("meta_ads.manage"))
      expect(card.at_css("a")["href"]).to eq("/admin/meta-ads")
    end
  end

  describe "ads to products" do
    let!(:alpha) { store.products.create!(name: "Chaussure Alpha", slug: "alpha", price_cents: 10_000, status: "active") }
    let!(:beta) { store.products.create!(name: "Sac Beta", slug: "beta", price_cents: 8_000, status: "active") }
    let(:foreign_product) { other_store.products.create!(name: "Montre Gamma", slug: "gamma", price_cents: 100, status: "active") }

    before do
      connect!
      patch "/admin/meta-ads/accounts", params: { ad_account_ids: %w[act_11] }
      account = store.meta_ads_ad_accounts.find_by!(meta_ad_account_id: "act_11")
      campaign = MetaAds::Campaign.create!(store: store, ad_account: account, meta_id: "111", name: "Promo")
      ad_set = MetaAds::AdSet.create!(store: store, ad_account: account, campaign: campaign, meta_id: "222", name: "Casa")
      @ad = MetaAds::Ad.create!(store: store, ad_account: account, ad_set: ad_set, campaign: campaign, meta_id: "333", name: "Video Chaussure Alpha")
      @idle = MetaAds::Ad.create!(store: store, ad_account: account, ad_set: ad_set, campaign: campaign, meta_id: "444", name: "No spend lately")
      MetaAds::DailyInsight.create!(store: store, ad_account: account, campaign: campaign, ad_set: ad_set, ad: @ad, level: "ad", date: Time.zone.today, currency: "EUR", spend: 3,
        synced_at: Time.current, meta_campaign_id: "111", meta_adset_id: "222", meta_ad_id: "333")
    end

    it "lists the ads that spent recently with their automatic link, and lets the merchant replace or remove it" do
      MetaAds::ProductMatcher.call(store: store)
      get "/admin/meta-ads"
      page = Nokogiri::HTML(response.body)
      expect(page.css("[data-meta-product-links] li").length).to eq(1)
      expect(page.at_css("[data-meta-product-links]").text).to include("Video Chaussure Alpha", I18n.t("meta_ads.link_source.auto"))
      expect(page.at_css("select[name='links[333]'] option[selected]").text).to eq("Chaussure Alpha")

      patch "/admin/meta-ads/product_links", params: { links: { "333" => beta.id.to_s } }
      expect(MetaAds::ProductLink.find_by!(object_type: "ad", meta_id: "333")).to have_attributes(product_id: beta.id, source: "manual")
      patch "/admin/meta-ads/product_links", params: { links: { "333" => "" } }
      expect(MetaAds::ProductLink.where(meta_id: "333")).to be_empty
    end

    it "ignores another store's product, an ad that is not listed, and tampered ids" do
      patch "/admin/meta-ads/product_links", params: { links: { "333" => foreign_product.id.to_s, "444" => alpha.id.to_s, "999" => alpha.id.to_s, "abc" => "x" } }
      expect(response).to redirect_to("/admin/meta-ads")
      expect(MetaAds::ProductLink.count).to eq(0)
    end
  end

  describe "dev status page" do
    it "shows connection state and last sync per ad account, never a token" do
      connect!
      patch "/admin/meta-ads/accounts", params: { ad_account_ids: %w[act_11] }
      store.meta_ads_ad_accounts.find_by!(meta_ad_account_id: "act_11").update!(last_synced_at: Time.zone.parse("2026-11-04 09:00"), sync_status: "ok")
      get "/admin/meta-ads/status"
      expect(response).to have_http_status(:ok)
      page = Nokogiri::HTML(response.body)
      expect(page.at_css("[data-meta-dev-status]").text).to include("active", "42", "ads_read, business_management")
      expect(page.at_css("[data-meta-dev-accounts]").text).to include("act_11", "2026-11-04 09:00", "ok")
      expect(response.body).not_to include(token, "synthetic-app-secret")
    end
  end

  %w[fr en ar].each do |locale|
    it "renders the page in #{locale} without missing translations" do
      connect!
      get "/admin/meta-ads", params: { locale: locale }
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("translation missing")
      expect(response.body).to include(I18n.t("meta_ads.connection", locale: locale))
    end
  end
end
