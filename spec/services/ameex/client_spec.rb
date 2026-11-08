# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ameex::Client do
  let(:store) { Store.create!(name: "Ameex Client #{SecureRandom.hex(4)}", slug: "ameex-c-#{SecureRandom.hex(4)}", currency: "MAD") }

  def response_double(code, body, headers = {})
    body = body.to_json unless body.is_a?(String)
    double = instance_double(Net::HTTPResponse, code: code.to_s, body: body)
    allow(double).to receive(:[]) { |name| headers[name.to_s.downcase] }
    double
  end

  before do
    account = store.delivery_accounts.create!(provider: "ameex", name: "Ameex", is_active: true)
    account.credentials = { "api_key" => "id-1", "api_secret" => "key-1" }
    account.save!
    store.reload
  end

  describe ".verify!" do
    it "loads cities with the API headers" do
      sent = nil
      allow(Net::HTTP).to receive(:start) do |*_args, &block|
        http = instance_double(Net::HTTP)
        allow(http).to receive(:request) { |request|
          sent = request
          response_double(200, { "data" => [ { "id" => 1, "name" => "Casablanca" } ] })
        }
        block.call(http)
      end
      expect(described_class.verify!(store, api_id: "id-1", api_key: "key-1")).to eq(true)
      expect(sent["C-Api-Id"]).to eq("id-1")
      expect(sent["C-Api-Key"]).to eq("key-1")
      expect(sent.uri.to_s).to include("/Delivery/Cities")
    end

    it "raises invalid_keys on Ameex login error pages" do
      allow_any_instance_of(described_class).to receive(:perform).and_return(
        response_double(200, { "login" => "error", "data" => { "pg_title" => "Page de connexion | AmeexApp" } })
      )
      expect {
        described_class.verify!(store, api_id: "bad", api_key: "bad")
      }.to raise_error(described_class::Error) { |e| expect(e.kind).to eq(:invalid_keys) }
    end
  end
end
