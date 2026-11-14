# frozen_string_literal: true

require "rails_helper"

RSpec.describe Morea::TrackingConsentJurisdiction do
  describe ".required?" do
    it "requires consent in the EU, EEA, UK and Switzerland" do
      expect(described_class.required?("FR")).to eq(true)
      expect(described_class.required?("de")).to eq(true)
      expect(described_class.required?("GB")).to eq(true)
      expect(described_class.required?("NO")).to eq(true)
      expect(described_class.required?("CH")).to eq(true)
    end

    it "does not require consent in African markets" do
      %w[MA DZ TN EG NG ZA KE SN CI GH].each do |code|
        expect(described_class.required?(code)).to eq(false), "expected #{code} not to require cookie consent"
      end
    end

    it "does not require consent when the country is unknown" do
      expect(described_class.required?(nil)).to eq(false)
      expect(described_class.required?("")).to eq(false)
      expect(described_class.required?("XX")).to eq(false)
    end
  end

  describe ".country_from_request" do
    def request_with(headers)
      ActionDispatch::TestRequest.create.tap do |req|
        headers.each { |key, value| req.headers[key] = value }
      end
    end

    it "reads Cloudflare, CloudFront and Vercel country headers" do
      expect(described_class.country_from_request(request_with("CF-IPCountry" => "ma"))).to eq("MA")
      expect(described_class.country_from_request(request_with("CloudFront-Viewer-Country" => "FR"))).to eq("FR")
      expect(described_class.country_from_request(request_with("X-Vercel-IP-Country" => "GB"))).to eq("GB")
    end

    it "ignores Cloudflare unknown XX" do
      expect(described_class.country_from_request(request_with("CF-IPCountry" => "XX"))).to be_nil
    end
  end
end
