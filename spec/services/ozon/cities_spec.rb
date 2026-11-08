# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ozon::Cities do
  let(:payload) do
    {
      "CITIES" => {
        "1" => { "ID" => 1, "REF" => "CASA", "NAME" => "Casablanca", "DELIVERED-PRICE" => 25 },
        "2" => { "ID" => 2, "REF" => "RBA", "NAME" => "Rabat", "DELIVERED-PRICE" => 30 }
      }
    }
  end

  before do
    Rails.cache.clear
    allow(described_class).to receive(:public_cities).and_return(payload)
  end

  it "parses the public cities catalog" do
    cities = described_class.all
    expect(cities.map { |c| c[:name] }).to eq(%w[Casablanca Rabat])
    expect(cities.first[:delivered_price]).to eq(25)
  end

  it "matches a free-text city name" do
    expect(described_class.match(store: nil, city: "casablanca")[:id]).to eq(1)
  end
end
