# frozen_string_literal: true

require "rails_helper"
require "support/meta_ads_helpers"

RSpec.describe "Meta Ads authorization services" do
  let(:store) { Store.create!(slug: "meta-auth-#{SecureRandom.hex(5)}", name: "Synthetic", currency: "MAD") }
  let(:user) { store.users.create!(email: "meta-auth-#{SecureRandom.hex(4)}@example.test", password: "synthetic-meta-password-123", admin: true) }
  let(:session) { {} }

  before { stub_meta_env }

  def start(user_id: user.id)
    url = MetaAds::Oauth.authorization_url(store: store, session: session, user_id: user_id)
    [ url, Rack::Utils.parse_nested_query(URI(url).query) ]
  end

  describe MetaAds::Config do
    it "reads everything from the environment" do
      expect(described_class).to be_configured
      expect(described_class.redirect_uri).to eq("http://lvh.me/auth/meta/callback")
      expect(described_class.login_config_id).to eq("synthetic-config-id")
      expect(described_class.api_version).to eq("v25.0")
    end

    it "takes the Graph version from META_GRAPH_VERSION and refuses a malformed one" do
      stub_meta_env("META_GRAPH_VERSION" => "v26.0")
      expect(described_class.api_version).to eq("v26.0")
      stub_meta_env("META_GRAPH_VERSION" => "latest")
      expect { described_class.api_version }.to raise_error(ArgumentError)
    end

    it "is not configured when any of the four settings is missing" do
      MetaAdsHelpers::META_ENV.each_key do |key|
        stub_meta_env(key => nil)
        expect(described_class).not_to be_configured, "expected #{key} to be required"
      end
    end

    it "only ever asks for ads_read and business_management" do
      expect(described_class::SCOPES).to eq(%w[ads_read business_management])
    end
  end

  describe MetaAds::Oauth do
    it "sends the merchant to Facebook Login for Business with the configuration id and a signed state" do
      url, query = start

      expect(url).to start_with("https://www.facebook.com/#{MetaAds::Config.api_version}/dialog/oauth?")
      expect(query).to include("client_id" => "synthetic-app-id", "config_id" => "synthetic-config-id", "response_type" => "code",
        "redirect_uri" => "http://lvh.me/auth/meta/callback", "override_default_response_type" => "true")
      expect(query).not_to have_key("scope")
      expect(query).not_to have_key("auth_type")
      expect(query["state"].length).to be > 64
      expect(store.reload.meta_ads_connection).to have_attributes(status: "disconnected", access_token: nil)
      expect(store.meta_ads_connection.oauth_state_digest).to be_present
    end

    it "asks Meta to re-prompt permissions when reconnecting after a prior grant" do
      MetaAds::Connection.create!(store: store, status: "disconnected", last_verified_at: 1.day.ago)
      _, query = start
      expect(query["auth_type"]).to eq("rerequest")

      store.meta_ads_connection.update!(status: "needs_reauthorization", last_verified_at: nil)
      _, query = start
      expect(query["auth_type"]).to eq("rerequest")
    end

    it "does not start without the Meta settings" do
      stub_meta_env("META_LOGIN_CONFIG_ID" => nil)
      expect { start }.to raise_error(MetaAds::Oauth::Error) { |error| expect(error.code).to eq("config_missing") }
    end

    it "accepts a callback once, bound to the session, the store and the user" do
      _, query = start
      pending = MetaAds::Oauth.pending_for(params: { state: query["state"] }, session: session)
      expect(pending).to have_attributes(store: store, user: user)

      code = MetaAds::Oauth.consume!(pending: pending, params: { code: "synthetic-code" }, session: session)
      expect(code).to eq("synthetic-code")
      expect(store.meta_ads_connection.reload.oauth_state_digest).to be_nil
      expect(session).not_to have_key(:meta_ads_oauth)
      expect { MetaAds::Oauth.pending_for(params: { state: query["state"] }, session: session) }
        .to raise_error(MetaAds::Oauth::Error) { |error| expect(error.code).to eq("invalid_state") }
    end

    it "rejects a forged state, a state from another session, a tampered state and an expired one" do
      _, query = start
      forged = MetaAds::Oauth.send(:verifier).generate({ "n" => "x", "s" => store.id, "u" => user.id }, expires_in: 5.minutes, purpose: "other-purpose")
      [ SecureRandom.hex(32), forged, query["state"] + "x", "" ].each do |state|
        expect { MetaAds::Oauth.pending_for(params: { state: state }, session: session.deep_dup) }
          .to raise_error(MetaAds::Oauth::Error) { |error| expect(error.code).to eq("invalid_state") }
      end
      expect { MetaAds::Oauth.pending_for(params: { state: query["state"] }, session: {}) }
        .to raise_error(MetaAds::Oauth::Error) { |error| expect(error.code).to eq("invalid_state") }
      travel_to(11.minutes.from_now) do
        expect { MetaAds::Oauth.pending_for(params: { state: query["state"] }, session: session) }
          .to raise_error(MetaAds::Oauth::Error) { |error| expect(error.code).to eq("invalid_state") }
      end
    end

    it "rejects a state whose user is not staff of the store anymore" do
      _, query = start
      user.update!(status: "suspended")
      expect { MetaAds::Oauth.pending_for(params: { state: query["state"] }, session: session) }
        .to raise_error(MetaAds::Oauth::Error) { |error| expect(error.code).to eq("invalid_state") }
    end

    it "reports a denied authorization after the state was checked" do
      _, query = start
      pending = MetaAds::Oauth.pending_for(params: { state: query["state"] }, session: session)
      expect { MetaAds::Oauth.consume!(pending: pending, params: { error: "access_denied" }, session: session) }
        .to raise_error(MetaAds::Oauth::Error) { |error| expect(error.code).to eq("authorization_denied") }
    end
  end

  describe MetaAds::Authorizer do
    let(:connection) { MetaAds::Oauth.send(:find_or_create_connection, store) }
    let(:requests) { [] }
    let(:debug_data) { { is_valid: true, scopes: %w[ads_read business_management public_profile], user_id: "9001", expires_at: 55.days.from_now.to_i } }
    let(:transport) do
      lambda do |uri, request|
        requests << [ uri, request ]
        case uri.path
        when %r{/oauth/access_token}
          form = URI.decode_www_form(request.body).to_h
          form["grant_type"] == "fb_exchange_token" ? meta_reply(access_token: "synthetic-long-token", expires_in: 5_184_000) : meta_reply(access_token: "synthetic-short-token")
        when %r{/debug_token} then meta_reply(data: debug_data)
        else raise "Unexpected #{uri}"
        end
      end
    end

    it "exchanges the code for a short-lived then a long-lived token and stores it encrypted with scopes and expiry" do
      described_class.new(connection: connection, transport: transport).authorize!(code: "synthetic-code")

      expect(connection.reload).to have_attributes(status: "active", granted_scopes: %w[ads_read business_management public_profile], meta_user_id: "9001", last_error_code: nil)
      expect(connection.access_token).to eq("synthetic-long-token")
      expect(connection.access_token_ciphertext).not_to include("synthetic-long-token")
      expect(connection.token_expires_at).to be_within(5.seconds).of(Time.at(debug_data[:expires_at]))
      forms = requests.select { |uri, _| uri.path.end_with?("/oauth/access_token") }.map { |_, request| URI.decode_www_form(request.body).to_h }
      expect(forms.first).to include("code" => "synthetic-code", "redirect_uri" => "http://lvh.me/auth/meta/callback", "client_secret" => "synthetic-app-secret")
      expect(forms.last).to include("grant_type" => "fb_exchange_token", "fb_exchange_token" => "synthetic-short-token")
      # The secret and the code never travel in URLs.
      expect(requests.map { |uri, _| uri.to_s }.join).not_to include("synthetic-app-secret", "synthetic-code")
    end

    it "refuses a token without ads_read but accepts one without business_management" do
      debug_data[:scopes] = %w[public_profile]
      expect { described_class.new(connection: connection, transport: transport).authorize!(code: "c") }
        .to raise_error(MetaAds::Oauth::Error) { |error| expect(error.code).to eq("missing_scopes") }
      expect(connection.reload).to have_attributes(status: "disconnected", access_token: nil)

      debug_data[:scopes] = %w[ads_read]
      described_class.new(connection: connection, transport: transport).authorize!(code: "c")
      expect(connection.reload.granted_scopes).to eq(%w[ads_read])
    end

    it "maps a rejected code and Meta downtime to fixed codes without echoing Meta's text" do
      rejected = ->(_uri, _request) { meta_reply({ error: { code: 100, message: "Invalid code synthetic-code" } }, status: 400) }
      expect { described_class.new(connection: connection, transport: rejected).authorize!(code: "c") }
        .to raise_error(MetaAds::Oauth::Error) { |error| expect(error.code).to eq("authorization_failed"); expect(error.message).not_to include("synthetic-code") }
      down = ->(_uri, _request) { meta_reply({}, status: 503) }
      expect { described_class.new(connection: connection, transport: down).authorize!(code: "c") }
        .to raise_error(MetaAds::Oauth::Error) { |error| expect(error.code).to eq("unavailable") }
    end

    it "reconnects the same row after authorization was lost" do
      connection.update!(status: "needs_reauthorization", last_error_code: "invalid_token")
      described_class.new(connection: connection, transport: transport).authorize!(code: "c")

      expect(MetaAds::Connection.where(store: store).count).to eq(1)
      expect(connection.reload).to have_attributes(status: "active", last_error_code: nil)
    end
  end

  describe "account discovery and selection" do
    let(:connection) { MetaAds::Connection.create!(store: store, access_token: "synthetic-token") }
    let(:rows) do
      [ { id: "act_11", name: "Main", currency: "EUR", account_status: 1, timezone_name: "Europe/Paris" },
        { id: "act_22", name: "Second", currency: "USD", account_status: 1, timezone_name: "America/New_York" },
        { id: "act_33", name: "Unpaid", currency: "USD", account_status: 3, timezone_name: "UTC" },
        { id: "act_44", name: "Disabled", currency: "USD", account_status: 2, timezone_name: "UTC" },
        { id: "not-an-id", name: "Bad" } ]
    end
    let(:requests) { [] }
    let(:transport) do
      lambda do |uri, _request|
        requests << uri
        meta_reply(data: rows)
      end
    end

    def discover
      MetaAds::AccountDiscovery.new(connection: connection, transport: transport).call
    end

    it "asks Meta for id, name, currency, account_status and timezone_name" do
      discover
      expect(Rack::Utils.parse_nested_query(requests.first.query)["fields"].split(",")).to match_array(%w[id name currency account_status timezone_name])
    end

    it "caches valid accounts with currency, status and timezone, unselected, and is repeatable" do
      expect(discover.map(&:meta_ad_account_id)).to eq(%w[act_11 act_22 act_33 act_44])
      expect { discover }.not_to change(MetaAds::AdAccount, :count)
      expect(store.meta_ads_ad_accounts.find_by!(meta_ad_account_id: "act_11")).to have_attributes(currency: "EUR", timezone_name: "Europe/Paris", account_status: 1, selected: false)
    end

    it "treats only active accounts as selectable" do
      discover
      selectable = store.meta_ads_ad_accounts.order(:meta_ad_account_id).to_h { |account| [ account.meta_ad_account_id, account.selectable? ] }
      expect(selectable).to eq("act_11" => true, "act_22" => true, "act_33" => false, "act_44" => false)
      expect { MetaAds::AccountSelection.call(connection: connection, ids: %w[act_33]) }
        .to raise_error(MetaAds::AccountSelection::Error) { |error| expect(error.code).to eq("account_not_selectable") }
      expect(store.meta_ads_ad_accounts.selected.count).to eq(0)
    end

    it "unselects an account that became disabled" do
      discover
      MetaAds::AccountSelection.call(connection: connection, ids: %w[act_11])
      rows.first[:account_status] = 2
      discover
      expect(store.meta_ads_ad_accounts.find_by!(meta_ad_account_id: "act_11")).to have_attributes(selected: false, account_status: 2)
    end

    it "selects several accounts, keeps the selection on refresh and unselects omitted accounts" do
      discover
      MetaAds::AccountSelection.call(connection: connection, ids: %w[act_11 act_22])
      expect(store.meta_ads_ad_accounts.selected.count).to eq(2)
      expect(store.meta_ads_ad_accounts.selected.pluck(:next_sync_at)).to all(be_present)

      discover
      expect(store.meta_ads_ad_accounts.selected.count).to eq(2)
      MetaAds::AccountSelection.call(connection: connection, ids: %w[act_22])
      expect(store.meta_ads_ad_accounts.selected.pluck(:meta_ad_account_id)).to eq(%w[act_22])
    end

    it "refuses unknown ids and an account another store already syncs" do
      discover
      expect { MetaAds::AccountSelection.call(connection: connection, ids: %w[act_999]) }
        .to raise_error(MetaAds::AccountSelection::Error) { |error| expect(error.code).to eq("unknown_account") }

      other_store = Store.create!(slug: "meta-rival-#{SecureRandom.hex(5)}", name: "Rival", currency: "MAD")
      other_connection = MetaAds::Connection.create!(store: other_store, access_token: "synthetic-other")
      MetaAds::AccountDiscovery.new(connection: other_connection, transport: transport).call
      MetaAds::AccountSelection.call(connection: other_connection, ids: %w[act_11])

      expect { MetaAds::AccountSelection.call(connection: connection, ids: %w[act_11]) }
        .to raise_error(MetaAds::AccountSelection::Error) { |error| expect(error.code).to eq("already_connected") }
      expect(store.meta_ads_ad_accounts.selected.count).to eq(0)
    end

    it "does not select anything while reauthorization is required" do
      discover
      connection.mark_needs_reauthorization!("invalid_token")
      expect { MetaAds::AccountSelection.call(connection: connection, ids: %w[act_11]) }
        .to raise_error(MetaAds::AccountSelection::Error) { |error| expect(error.code).to eq("reauthorization_required") }
    end
  end
end
