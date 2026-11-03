# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Meta Ads authorization services" do
  let(:store) { Store.create!(slug: "meta-auth-#{SecureRandom.hex(5)}", name: "Synthetic", currency: "MAD") }
  let(:session) { {} }
  let(:callback_url) { "https://morea.test/admin/meta-ads/callback" }

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("META_APP_ID").and_return("synthetic-app-id")
    allow(ENV).to receive(:[]).with("META_APP_SECRET").and_return("synthetic-app-secret")
  end

  def reply(body = nil, status: 200, **fields)
    body ||= fields
    Struct.new(:code, :body, :to_hash).new(status.to_s, body.to_json, {})
  end

  def start(user_id: 7)
    url = MetaAds::Oauth.authorization_url(store: store, session: session, user_id: user_id, callback_url: callback_url)
    [ url, Rack::Utils.parse_nested_query(URI(url).query) ]
  end

  describe MetaAds::Oauth do
    it "asks only for read access and creates a token-less placeholder connection" do
      url, query = start

      expect(url).to start_with("https://www.facebook.com/#{MetaAds::Config.api_version}/dialog/oauth?")
      expect(query).to include("client_id" => "synthetic-app-id", "scope" => "ads_read", "redirect_uri" => callback_url)
      expect(query["scope"]).not_to include("ads_management")
      expect(store.reload.meta_ads_connection).to have_attributes(status: "disconnected", access_token: nil)
      expect(store.meta_ads_connection.oauth_state_digest).to eq(Digest::SHA256.hexdigest(query["state"]))
    end

    it "does not start without Meta app credentials" do
      allow(ENV).to receive(:[]).with("META_APP_ID").and_return(nil)
      expect { start }.to raise_error(MetaAds::Oauth::Error) { |error| expect(error.code).to eq("config_missing") }
    end

    it "accepts a callback once and clears the state" do
      _, query = start
      connection, code = MetaAds::Oauth.consume_callback!(params: { state: query["state"], code: "synthetic-code" }, session: session, store: store, user_id: 7)

      expect(code).to eq("synthetic-code")
      expect(connection.reload.oauth_state_digest).to be_nil
      expect { MetaAds::Oauth.consume_callback!(params: { state: query["state"], code: "x" }, session: session, store: store, user_id: 7) }
        .to raise_error(MetaAds::Oauth::Error) { |error| expect(error.code).to eq("invalid_state") }
    end

    it "rejects another user, another store, a wrong state and an expired state" do
      _, query = start
      other_store = Store.create!(slug: "meta-other-#{SecureRandom.hex(5)}", name: "Other", currency: "MAD")

      [ { user_id: 8, store: store, state: query["state"] }, { user_id: 7, store: other_store, state: query["state"] },
        { user_id: 7, store: store, state: SecureRandom.hex(32) } ].each do |attempt|
        copy = session.deep_dup
        expect { MetaAds::Oauth.consume_callback!(params: { state: attempt[:state], code: "c" }, session: copy, store: attempt[:store], user_id: attempt[:user_id]) }
          .to raise_error(MetaAds::Oauth::Error) { |error| expect(error.code).to eq("invalid_state") }
      end
      travel_to(11.minutes.from_now) do
        expect { MetaAds::Oauth.consume_callback!(params: { state: query["state"], code: "c" }, session: session, store: store, user_id: 7) }
          .to raise_error(MetaAds::Oauth::Error) { |error| expect(error.code).to eq("authorization_expired") }
      end
    end

    it "reports a denied authorization" do
      _, query = start
      expect { MetaAds::Oauth.consume_callback!(params: { state: query["state"], error: "access_denied" }, session: session, store: store, user_id: 7) }
        .to raise_error(MetaAds::Oauth::Error) { |error| expect(error.code).to eq("authorization_denied") }
    end
  end

  describe MetaAds::Authorizer do
    let(:connection) { MetaAds::Oauth.send(:find_or_create_connection, store) }
    let(:requests) { [] }
    let(:debug_data) { { is_valid: true, scopes: %w[ads_read public_profile], user_id: "9001", expires_at: 4.days.from_now.to_i } }
    let(:transport) do
      lambda do |uri, request|
        requests << [ uri, request ]
        case uri.path
        when %r{/oauth/access_token}
          form = URI.decode_www_form(request.body).to_h
          form["grant_type"] == "fb_exchange_token" ? reply(access_token: "synthetic-long-token", expires_in: 5_184_000) : reply(access_token: "synthetic-short-token")
        when %r{/debug_token} then reply(data: debug_data)
        else raise "Unexpected #{uri}"
        end
      end
    end

    it "stores an encrypted long-lived token with granted scopes and expiry, keeping secrets out of URLs" do
      described_class.new(connection: connection, redirect_uri: callback_url, transport: transport).authorize!(code: "synthetic-code")

      expect(connection.reload).to have_attributes(status: "active", granted_scopes: %w[ads_read public_profile], meta_user_id: "9001", last_error_code: nil)
      expect(connection.access_token).to eq("synthetic-long-token")
      expect(connection.access_token_ciphertext).not_to include("synthetic-long-token")
      expect(connection.token_expires_at).to be_within(5.seconds).of(Time.at(debug_data[:expires_at]))
      # Meta's documented debug_token call takes the inspected token as a query parameter; the secret and code never travel in URLs.
      expect(requests.map { |uri, _| uri.to_s }.join).not_to include("synthetic-app-secret", "synthetic-code")
      expect(requests.map { |_, request| request["Authorization"] }.compact).to all(eq("Bearer synthetic-app-id|synthetic-app-secret"))
      expect(URI.decode_www_form(requests.first.last.body).to_h).to include("code" => "synthetic-code", "client_secret" => "synthetic-app-secret")
    end

    it "refuses a token without ads_read" do
      debug_data[:scopes] = %w[public_profile]
      expect { described_class.new(connection: connection, redirect_uri: callback_url, transport: transport).authorize!(code: "c") }
        .to raise_error(MetaAds::Oauth::Error) { |error| expect(error.code).to eq("missing_scopes") }
      expect(connection.reload).to have_attributes(status: "disconnected", access_token: nil)
    end

    it "maps a rejected code and Meta downtime to fixed codes" do
      rejected = ->(_uri, _request) { reply({ error: { code: 100, message: "Invalid code synthetic-code" } }, status: 400) }
      expect { described_class.new(connection: connection, redirect_uri: callback_url, transport: rejected).authorize!(code: "c") }
        .to raise_error(MetaAds::Oauth::Error) { |error| expect(error.code).to eq("authorization_failed"); expect(error.message).not_to include("synthetic-code") }
      down = ->(_uri, _request) { reply({}, status: 503) }
      expect { described_class.new(connection: connection, redirect_uri: callback_url, transport: down).authorize!(code: "c") }
        .to raise_error(MetaAds::Oauth::Error) { |error| expect(error.code).to eq("unavailable") }
    end

    it "reconnects the same row after authorization was lost" do
      connection.update!(status: "needs_reauthorization", last_error_code: "invalid_token")
      described_class.new(connection: connection, redirect_uri: callback_url, transport: transport).authorize!(code: "c")

      expect(MetaAds::Connection.where(store: store).count).to eq(1)
      expect(connection.reload).to have_attributes(status: "active", last_error_code: nil)
    end
  end

  describe "account discovery and selection" do
    let(:connection) { MetaAds::Connection.create!(store: store, access_token: "synthetic-token") }
    let(:rows) do
      [ { id: "act_11", name: "Main", currency: "EUR", timezone_name: "Europe/Paris" },
        { id: "act_22", name: "Second", currency: "USD", timezone_name: "America/New_York" }, { id: "not-an-id", name: "Bad" } ]
    end
    let(:transport) { ->(_uri, _request) { reply(data: rows) } }

    def discover
      MetaAds::AccountDiscovery.new(connection: connection, transport: transport).call
    end

    it "caches valid accounts with currency and timezone, unselected, and is repeatable" do
      expect(discover.map(&:meta_ad_account_id)).to eq(%w[act_11 act_22])
      expect { discover }.not_to change(MetaAds::AdAccount, :count)
      expect(store.meta_ads_ad_accounts.find_by!(meta_ad_account_id: "act_11")).to have_attributes(currency: "EUR", timezone_name: "Europe/Paris", selected: false)
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
