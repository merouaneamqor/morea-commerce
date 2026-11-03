# frozen_string_literal: true

require "rails_helper"

RSpec.describe Sendit::Client do
  let(:store) { Store.create!(name: "Client #{SecureRandom.hex(4)}", slug: "client-#{SecureRandom.hex(5)}", currency: "MAD") }

  def response_double(code, body)
    instance_double(Net::HTTPResponse, code: code.to_s, body: body.to_json)
  end

  describe ".verify!" do
    it "logs in with the public and secret keys and returns Sendit's token" do
      requests = []
      allow_any_instance_of(described_class).to receive(:perform) do |_client, method, uri, body, bearer|
        requests << [ method, uri.to_s, body, bearer ]
        response_double(200, { success: true, data: { token: "abc123" } })
      end
      expect(described_class.verify!(store, public_key: "pub", secret_key: "sec")).to eq("abc123")
      expect(requests).to eq([ [ :post, "https://app.sendit.ma/api/v1/login", { public_key: "pub", secret_key: "sec" }, nil ] ])
    end

    it "raises with the HTTP status when Sendit refuses the keys" do
      allow_any_instance_of(described_class).to receive(:perform).and_return(response_double(401, { success: false, message: "Identifiants invalides" }))
      expect { described_class.verify!(store, public_key: "pub", secret_key: "bad") }
        .to raise_error(described_class::Error) { |error| expect(error).to have_attributes(status: 401, message: "Identifiants invalides") }
    end

    it "raises when Sendit answers without a token" do
      allow_any_instance_of(described_class).to receive(:perform).and_return(response_double(200, { success: true, data: {} }))
      expect { described_class.verify!(store, public_key: "pub", secret_key: "sec") }.to raise_error(described_class::Error, /no token/)
    end

    it "does not use or fill the workspace's cached session" do
      allow_any_instance_of(described_class).to receive(:perform).and_return(response_double(200, { success: true, data: { token: "abc123" } }))
      expect(Rails.cache).not_to receive(:fetch)
      described_class.verify!(store, public_key: "pub", secret_key: "sec")
    end
  end
end
