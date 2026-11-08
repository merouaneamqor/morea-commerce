# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ozon::Client do
  let(:store) { Store.create!(name: "Ozon Client #{SecureRandom.hex(4)}", slug: "ozon-c-#{SecureRandom.hex(4)}", currency: "MAD") }

  def response_double(code, body, headers = {})
    body = body.to_json unless body.is_a?(String)
    double = instance_double(Net::HTTPResponse, code: code.to_s, body: body)
    allow(double).to receive(:[]) { |name| headers[name.to_s.downcase] }
    double
  end

  before do
    account = store.delivery_accounts.create!(provider: "ozon", name: "Ozon", is_active: true)
    account.credentials = { "api_key" => "44492", "api_secret" => "secret-key" }
    account.save!
    store.reload
  end

  describe ".verify!" do
    it "accepts credentials when parcel-info answers with a business rejection" do
      allow_any_instance_of(described_class).to receive(:perform_form).and_return(
        response_double(400, { "ERROR" => "Parcel not found" })
      )
      expect(described_class.verify!(store, customer_id: "44492", api_key: "secret-key")).to eq(true)
    end

    it "raises invalid_keys when Ozon refuses the credentials" do
      allow_any_instance_of(described_class).to receive(:perform_form).and_return(
        response_double(401, { "message" => "Invalid API key" })
      )
      expect {
        described_class.verify!(store, customer_id: "44492", api_key: "bad")
      }.to raise_error(described_class::Error) { |e| expect(e.kind).to eq(:invalid_keys) }
    end
  end

  describe "#add_parcel" do
    it "posts form fields under the customer path" do
      sent = nil
      allow(Net::HTTP).to receive(:start) do |*_args, &block|
        http = instance_double(Net::HTTP)
        allow(http).to receive(:request) { |request|
          sent = request
          response_double(200, { "TRACKING-NUMBER" => "OZE1", "CITY_NAME" => "Casablanca" })
        }
        block.call(http)
      end

      data = described_class.new(store).add_parcel(
        "parcel-receiver" => "Karim",
        "parcel-phone" => "0612345678",
        "parcel-city" => "1",
        "parcel-address" => "Rue 1",
        "parcel-price" => "250",
        "parcel-stock" => "0"
      )

      expect(data["TRACKING-NUMBER"]).to eq("OZE1")
      expect(sent).to be_a(Net::HTTP::Post)
      expect(sent.uri.to_s).to include("/customers/44492/secret-key/add-parcel")
    end
  end
end
