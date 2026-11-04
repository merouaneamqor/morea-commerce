# frozen_string_literal: true

require "rails_helper"

RSpec.describe MetaAds::Client do
  let(:store) { Store.create!(slug: "meta-client-#{SecureRandom.hex(5)}", name: "Synthetic", currency: "MAD") }
  let(:connection) { MetaAds::Connection.create!(store: store, access_token: "synthetic-meta-token") }
  let(:requests) { [] }
  let(:responses) { [] }
  let(:transport) do
    lambda do |uri, request|
      requests << [ uri, request ]
      raise "Unexpected HTTP call" if responses.empty?

      responses.shift
    end
  end
  subject(:client) { described_class.new(connection: connection, transport: transport) }

  def reply(status: 200, body: {}, headers: {})
    Struct.new(:code, :body, :to_hash).new(status.to_s, body.to_json, headers.transform_values { |value| [ value ] })
  end

  it "sends the token as a bearer header, never in the URL, against the configured version" do
    responses << reply(body: { data: [] })
    client.get("act_1/campaigns", fields: %w[id name])

    uri, request = requests.first
    expect(uri.to_s).to start_with("https://graph.facebook.com/#{MetaAds::Config.api_version}/act_1/campaigns?")
    expect(uri.to_s).to include("fields=id%2Cname")
    expect(uri.to_s).not_to include("synthetic-meta-token")
    expect(request["Authorization"]).to eq("Bearer synthetic-meta-token")
  end

  it "uses the version from META_GRAPH_API_VERSION and rejects malformed values" do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("META_GRAPH_API_VERSION").and_return("v99.0")
    expect(MetaAds::Config.api_version).to eq("v99.0")
    allow(ENV).to receive(:[]).with("META_GRAPH_API_VERSION").and_return("../evil")
    expect { MetaAds::Config.api_version }.to raise_error(ArgumentError)
  end

  it "follows cursors until the collection is complete and reports the highest usage" do
    responses << reply(body: { data: [ { id: "1" } ], paging: { cursors: { after: "A" }, next: "https://example.invalid/ignored" } },
      headers: { "x-app-usage" => { call_count: 10, total_cputime: 5, total_time: 5 }.to_json })
    responses << reply(body: { data: [ { id: "2" } ], paging: { cursors: { after: "B" } } },
      headers: { "x-ad-account-usage" => { acc_id_util_pct: 42.5 }.to_json })

    result = client.collect("act_1/campaigns", fields: "id")

    expect(result.data.map { |row| row["id"] }).to eq(%w[1 2])
    expect(result.usage_pct).to eq(42.5)
    expect(requests.last.first.to_s).to include("after=A")
    expect(requests.map { |uri, _| uri.host }.uniq).to eq([ "graph.facebook.com" ])
  end

  it "reads business use case usage and the time until access returns" do
    usage = { "1001" => [ { type: "ads_insights", call_count: 91, total_cputime: 12, total_time: 20, estimated_time_to_regain_access: 7 } ] }
    responses << reply(status: 400, body: { error: { code: 80000, message: "secret text" } }, headers: { "x-business-use-case-usage" => usage.to_json })

    expect { client.get("act_1/insights") }.to raise_error(MetaAds::Client::RateLimitError) { |error|
      expect(error.retry_after).to eq(420)
      expect(error.message).not_to include("secret text")
    }
  end

  {
    "invalid token" => [ 400, 190, MetaAds::Client::AuthError ],
    "unauthorized status" => [ 401, 0, MetaAds::Client::AuthError ],
    "missing permission" => [ 403, 200, MetaAds::Client::PermissionError ],
    "app rate limit" => [ 400, 4, MetaAds::Client::RateLimitError ],
    "too many requests" => [ 429, 0, MetaAds::Client::RateLimitError ],
    "temporary issue" => [ 500, 2, MetaAds::Client::TransientError ],
    "unknown client error" => [ 400, 100, MetaAds::Client::InvalidResponseError ]
  }.each do |name, (status, code, error_class)|
    it "maps #{name} to #{error_class.name.demodulize}" do
      responses << reply(status: status, body: { error: { code: code, message: "Meta text with synthetic-meta-token" } })

      expect { client.get("me") }.to raise_error(error_class) { |error|
        expect(error.message).not_to include("synthetic-meta-token")
        expect(error.message).not_to include("Meta text")
      }
    end
  end

  it "maps network failures to a retryable error" do
    transport_error = ->(_uri, _request) { raise Errno::ECONNRESET }
    expect { described_class.new(connection: connection, transport: transport_error).get("me") }.to raise_error(MetaAds::Client::TransientError)
  end

  it "rejects malformed bodies and unsafe paths without calling Meta" do
    responses << Struct.new(:code, :body, :to_hash).new("200", "not json", {})
    expect { client.get("me") }.to raise_error(MetaAds::Client::InvalidResponseError)
    expect { client.get("../me") }.to raise_error(ArgumentError)
    expect { client.get("me?access_token=x") }.to raise_error(ArgumentError)
    expect(requests.size).to eq(1)
  end

  it "refuses inactive connections and expired tokens" do
    expect { described_class.new(connection: MetaAds::Connection.new(store: store, status: "needs_reauthorization")) }.to raise_error(ArgumentError)
    connection.update!(token_expires_at: 1.minute.ago)
    expect { client.get("me") }.to raise_error(MetaAds::Client::AuthError)
    expect(requests).to be_empty
  end
end
