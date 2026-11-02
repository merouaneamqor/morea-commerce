# frozen_string_literal: true

require "rails_helper"

RSpec.describe Connections::SealloBridge do
  let(:secret) { "synthetic-bridge-key-for-tests-only-123456" }
  let(:body) { JSON.generate(shop: "synthetic-bridge.myshopify.com") }
  let(:timestamp) { Time.current.to_i.to_s }
  let(:signature) { OpenSSL::HMAC.hexdigest("sha256", secret, "#{timestamp}\n#{body}") }

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("SEALLO_BRIDGE_SECRET").and_return(secret)
  end

  def authenticate(**overrides)
    described_class.authenticate!(**{ body: body, timestamp: timestamp, signature: signature }.merge(overrides))
  end

  it "accepts only the exact raw body signed with the separate bridge key" do
    expect { authenticate }.not_to raise_error
    expect { authenticate(body: body + " ") }.to raise_error(described_class::Error, "invalid_signature")
    expect { authenticate(signature: "0" * 64) }.to raise_error(described_class::Error, "invalid_signature")
  end

  it "rejects expired, future and malformed timestamps" do
    [ 301.seconds.ago.to_i.to_s, 301.seconds.from_now.to_i.to_s, "invalid", "0" ].each do |value|
      signed = OpenSSL::HMAC.hexdigest("sha256", secret, "#{value}\n#{body}")
      expect { authenticate(timestamp: value, signature: signed) }.to raise_error(described_class::Error, "invalid_signature")
    end
  end

  it "rejects oversized envelopes even with a correct signature" do
    large_body = "x" * (described_class::MAX_BODY + 1)
    signed = OpenSSL::HMAC.hexdigest("sha256", secret, "#{timestamp}\n#{large_body}")
    expect { authenticate(body: large_body, signature: signed) }.to raise_error(described_class::Error, "invalid_signature")
  end

  it "fails closed when the bridge key is missing or too short" do
    allow(ENV).to receive(:[]).with("SEALLO_BRIDGE_SECRET").and_return("short")
    expect { authenticate }.to raise_error(described_class::Error, "config_missing")
  end

  it "refuses insecure or credential-bearing proxy origins before contacting the network" do
    allow(ENV).to receive(:fetch).and_call_original
    [ "http://synthetic.test", "https://user:password@synthetic.test", "https://synthetic.test/path", "https://synthetic.test?redirect=other" ].each do |origin|
      allow(ENV).to receive(:fetch).with("SEALLO_APP_URL", "").and_return(origin)
      expect(Net::HTTP).not_to receive(:new)
      expect { described_class.graphql(shop: "synthetic.myshopify.com", query: "query { shop { myshopifyDomain } }") }
        .to raise_error(described_class::Error, "config_missing")
    end
  end
end
