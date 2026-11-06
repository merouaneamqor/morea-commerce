# frozen_string_literal: true

require "rails_helper"

RSpec.describe Connections::YoucanOauth do
  let(:secret) { "synthetic-youcan-client-secret" }
  let(:store) { Store.create!(slug: "youcan-#{SecureRandom.hex(4)}", name: "Synthetic YouCan workspace", currency: "MAD", storefront_enabled: false) }
  let(:store_id) { "0ff0817b-4f5a-43e9-b42d-066363aa45e3" }
  let(:requests) { [] }
  let(:responses) { [] }
  let(:transport) do
    lambda do |uri, request|
      requests << [ uri, request ]
      response = responses.shift || raise("Unexpected HTTP call #{uri}")
      raise response if response.is_a?(Exception)

      response
    end
  end

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("YOUCAN_CLIENT_ID").and_return("cl_synthetic")
    allow(ENV).to receive(:[]).with("YOUCAN_CLIENT_SECRET").and_return(secret)
  end

  def http_response(status, data)
    Struct.new(:code, :body).new(status.to_s, JSON.generate(data))
  end

  def approve
    responses << http_response(200, access_token: "synthetic-access-token", expires_in: 86_400)
    responses << http_response(200, id: store_id, slug: "seallo", name: "Seallo", domain: "https://seallo.youcan.store")
    responses << http_response(200, id: "8e6b019b-06de-496d-a96d-c9ee69c0ccf0")
    described_class.connect!(store: store, code: "synthetic-code", transport: transport)
  end

  it "exchanges the approval, stores the store identity and subscribes order.created" do
    connection = approve

    token_request = requests[0]
    expect(token_request.first.to_s).to eq("https://api.youcan.shop/oauth/token")
    expect(URI.decode_www_form(token_request.last.body).to_h).to include(
      "grant_type" => "authorization_code",
      "client_id" => "cl_synthetic",
      "client_secret" => secret,
      "redirect_uri" => "#{Store.platform_origin}/admin/youcan/callback",
      "code" => "synthetic-code"
    )
    expect(requests[1].first.to_s).to eq("https://api.youcan.shop/me")
    expect(requests[1].last["Authorization"]).to eq("Bearer synthetic-access-token")
    expect(requests[2].first.to_s).to eq("https://api.youcan.shop/resthooks/subscribe")
    expect(JSON.parse(requests[2].last.body)).to eq(
      "event" => "order.created",
      "target_url" => "#{Store.platform_origin}/webhooks/store_orders/#{connection.token}"
    )
    expect(connection.provider).to eq("youcan")
    expect(connection.external_domain).to eq("seallo.youcan.store")
    expect(connection.external_store_id).to eq(store_id)
    expect(connection.name).to eq("Seallo")
    expect(connection.webhook_secret).to eq(secret)
    expect(connection.verified_at).to be_nil
  end

  it "reuses the same connection and delivery address when the store approves again" do
    first = approve
    responses << http_response(200, access_token: "synthetic-access-token-2", expires_in: 86_400)
    responses << http_response(200, id: store_id, slug: "seallo", name: "Seallo", domain: "seallo.youcan.store")
    responses << http_response(200, id: "8e6b019b-06de-496d-a96d-c9ee69c0ccf0")
    first.update!(active: false, verified_at: Time.current, last_error_code: "incomplete_payload")

    again = described_class.connect!(store: store, code: "synthetic-code-2", transport: transport)

    expect(again.id).to eq(first.id)
    expect(again.token).to eq(first.token)
    expect(again).to be_active
    expect(again.verified_at).to be_nil
    expect(again.last_error_code).to be_nil
    expect(store.store_connections.where(provider: "youcan").count).to eq(1)
  end

  it "does not keep a connection when YouCan refuses the subscription" do
    responses << http_response(200, access_token: "synthetic-access-token", expires_in: 86_400)
    responses << http_response(200, id: store_id, slug: "seallo", name: "Seallo", domain: "seallo.youcan.store")
    responses << http_response(403, detail: "missing scope")

    expect { described_class.connect!(store: store, code: "synthetic-code", transport: transport) }
      .to raise_error(described_class::Error) { |error| expect(error.code).to eq("invalid_credentials") }
    expect(store.store_connections.count).to eq(0)
  end

  it "rejects a code that is not an authorization code" do
    expect { described_class.connect!(store: store, code: "bad code", transport: transport) }
      .to raise_error(described_class::Error) { |error| expect(error.code).to eq("invalid_code") }
    expect(requests).to be_empty
  end
end
