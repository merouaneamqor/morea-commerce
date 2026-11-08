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
    it "loads cities from api.cities" do
      allow_any_instance_of(described_class).to receive(:perform).and_return(
        response_double(200, { "login" => "success", "api" => { "type" => "success", "cities" => { "129" => { "id" => 129, "name" => "Casablanca" } } } })
      )
      expect(described_class.verify!(store, api_id: "id-1", api_key: "key-1")).to eq(true)
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

  describe "#statuses" do
    it "returns the status hash from api.data.status" do
      allow_any_instance_of(described_class).to receive(:perform).and_return(
        response_double(200, {
          "login" => "success",
          "api" => { "type" => "success", "data" => { "status" => { "DELIVERED" => { "name" => "Livré", "color" => "#9ccc65" } } } }
        })
      )
      expect(described_class.new(store).statuses).to eq("DELIVERED" => { "name" => "Livré", "color" => "#9ccc65" })
    end
  end

  describe "#add_parcel" do
    it "returns the sandbox code from api.data" do
      allow_any_instance_of(described_class).to receive(:perform).and_return(
        response_double(200, {
          "login" => "success",
          "api" => { "type" => "success", "msg" => "Sandbox parcel created.", "data" => { "code" => "SBX-1" }, "sandbox" => 1 }
        })
      )
      expect(described_class.new(store).add_parcel("type" => "SIMPLE")).to include("code" => "SBX-1", "sandbox" => 1)
    end
  end
end
