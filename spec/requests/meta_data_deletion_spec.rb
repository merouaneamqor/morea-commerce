# frozen_string_literal: true

require "rails_helper"
require "support/meta_ads_helpers"

RSpec.describe "Meta data deletion callback", type: :request do
  let(:store) { Store.create!(slug: "meta-del-#{SecureRandom.hex(5)}", name: "Synthetic", currency: "MAD") }
  let(:other_store) { Store.create!(slug: "meta-del-b-#{SecureRandom.hex(5)}", name: "Other", currency: "MAD") }
  let(:unrelated_store) { Store.create!(slug: "meta-del-c-#{SecureRandom.hex(5)}", name: "Unrelated", currency: "MAD") }
  let(:payload) { { algorithm: "HMAC-SHA256", user_id: "9001", issued_at: Time.current.to_i } }

  before do
    stub_meta_env
    host! Store.base_domain
  end

  def connect(store, user_id)
    MetaAds::Connection.create!(store: store, access_token: "synthetic-token-#{user_id}", meta_user_id: user_id, granted_scopes: %w[ads_read], token_expires_at: 30.days.from_now)
  end

  it "verifies the signature, removes that Meta user's tokens in every store and answers with a status URL and confirmation code" do
    mine = connect(store, "9001")
    also_mine = connect(other_store, "9001")
    other_user = connect(unrelated_store, "7777")
    account = MetaAds::AdAccount.create!(store: store, connection: mine, meta_ad_account_id: "act_1", name: "A", currency: "EUR", timezone_name: "UTC", account_status: 1, selected: true)

    post "/auth/meta/data-deletion", params: { signed_request: meta_signed_request(payload) }

    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body["confirmation_code"]).to match(/\A[0-9a-f]{24}\z/)
    expect(body["url"]).to eq("#{Store.platform_origin}/auth/meta/data-deletion/#{body["confirmation_code"]}")
    [ mine, also_mine ].each { |connection| expect(connection.reload).to have_attributes(status: "disconnected", access_token: nil, access_token_ciphertext: nil, meta_user_id: nil, granted_scopes: []) }
    expect(account.reload.selected).to be(false)
    expect(other_user.reload).to have_attributes(status: "active", access_token: "synthetic-token-7777")
    request = MetaAds::DeletionRequest.find_by!(confirmation_code: body["confirmation_code"])
    expect(request).to have_attributes(status: "completed", connections_removed: 2, meta_user_digest: Digest::SHA256.hexdigest("9001"))
    expect(request.attributes.values.join).not_to include("9001-")
  end

  it "keeps the synced spend history" do
    connection = connect(store, "9001")
    account = MetaAds::AdAccount.create!(store: store, connection: connection, meta_ad_account_id: "act_1", name: "A", currency: "EUR", timezone_name: "UTC", account_status: 1, selected: true)
    campaign = MetaAds::Campaign.create!(store: store, ad_account: account, meta_id: "111", name: "C")
    MetaAds::DailyInsight.create!(store: store, ad_account: account, campaign: campaign, level: "campaign", date: Date.new(2026, 11, 3), currency: "EUR", spend: 5, synced_at: Time.current)

    post "/auth/meta/data-deletion", params: { signed_request: meta_signed_request(payload) }
    expect(MetaAds::DailyInsight.count).to eq(1)
  end

  it "answers with a code even when the user has no connection, so Meta always gets a receipt" do
    post "/auth/meta/data-deletion", params: { signed_request: meta_signed_request(payload) }
    expect(response).to have_http_status(:ok)
    expect(MetaAds::DeletionRequest.last).to have_attributes(connections_removed: 0)
  end

  it "refuses a bad signature, another secret, a bad algorithm, a malformed or missing request, and removes nothing" do
    connection = connect(store, "9001")
    [ meta_signed_request(payload, secret: "wrong-secret"), meta_signed_request(payload.merge(algorithm: "HMAC-SHA1")),
      meta_signed_request(payload.merge(user_id: "not-a-number")), meta_signed_request(payload).sub(/\A.{4}/, "AAAA"), "garbage", "a.b", "", nil ].each do |bad|
      post "/auth/meta/data-deletion", params: { signed_request: bad }
      expect(response).to have_http_status(:bad_request), "expected 400 for #{bad.inspect}"
      expect(response.parsed_body).to eq("error" => "invalid_signed_request")
    end
    expect(connection.reload).to have_attributes(status: "active", access_token: "synthetic-token-9001")
    expect(MetaAds::DeletionRequest.count).to eq(0)
  end

  it "needs the app secret to be configured" do
    stub_meta_env("META_APP_SECRET" => nil)
    post "/auth/meta/data-deletion", params: { signed_request: meta_signed_request(payload) }
    expect(response).to have_http_status(:bad_request)
  end

  it "serves a public status page for the confirmation code on the apex only" do
    post "/auth/meta/data-deletion", params: { signed_request: meta_signed_request(payload) }
    code = response.parsed_body["confirmation_code"]

    get "/auth/meta/data-deletion/#{code}"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(code, I18n.t("meta_ads.deletion.status.completed"))

    get "/auth/meta/data-deletion/#{"0" * 24}"
    expect(response).to have_http_status(:not_found)
    get "/auth/meta/data-deletion/not-a-code"
    expect(response).to have_http_status(:not_found)
    host! "#{store.slug}.#{Store.base_domain}"
    get "/auth/meta/data-deletion/#{code}"
    expect(response).to have_http_status(:not_found)
  end
end
