# frozen_string_literal: true

require "rails_helper"

RSpec.describe SenditCitiesRefreshJob do
  let(:suffix) { SecureRandom.hex(4) }
  let(:store) { Store.create!(name: "Cities #{suffix}", slug: "cities-#{suffix}", currency: "MAD") }
  let!(:account) { store.delivery_accounts.create!(provider: "sendit", name: "Sendit", credentials: { "api_key" => "pub", "api_secret" => "sec" }, webhook_token: "tok-#{suffix}-abcdefghij") }

  it "fetches the city list and records how many cities were synced" do
    allow(Sendit::Districts).to receive(:refresh!).with(store: store).and_return(districts: 321, pickup_cities: 40)
    described_class.perform_now(store.id)
    expect(account.reload).to have_attributes(cities_count: 321)
    expect(account.cities_synced_at).to be_within(1.minute).of(Time.current)
  end

  it "refreshes every workspace that has Sendit when run without an argument (the weekly run)" do
    other = Store.create!(name: "No Sendit #{suffix}", slug: "nosendit-#{suffix}", currency: "MAD")
    allow(Sendit::Districts).to receive(:refresh!).and_return(districts: 5, pickup_cities: 1)
    described_class.perform_now
    expect(Sendit::Districts).to have_received(:refresh!).with(store: store)
    expect(Sendit::Districts).not_to have_received(:refresh!).with(store: other)
  end

  it "leaves the previous counts and does not fail when Sendit is unreachable" do
    account.update!(cities_count: 12)
    allow(Sendit::Districts).to receive(:refresh!).and_raise(Sendit::Client::Error.new("Sendit unreachable"))
    expect { described_class.perform_now(store.id) }.not_to raise_error
    expect(account.reload.cities_count).to eq(12)
  end

  it "is scheduled weekly" do
    schedule = YAML.safe_load(ERB.new(Rails.root.join("config/schedule.yml").read).result)
    expect(schedule.fetch("sendit_cities_refresh")).to include("class" => "SenditCitiesRefreshJob", "cron" => "0 3 * * 1")
  end

  describe Sendit::Districts, ".refresh!" do
    it "drops the cached lists and fetches both lists again" do
      client = instance_double(Sendit::Client)
      allow(client).to receive(:districts).and_return("data" => [ { "id" => 1, "ville" => "Fès", "name" => "Fès", "price" => "35" }, { "id" => 2, "ville" => "Rabat", "name" => "Rabat", "price" => "30" } ], "last_page" => 1)
      allow(client).to receive(:pickup_cities).and_return([ { "id" => 9, "name" => "Casablanca" } ])
      expect(Rails.cache).to receive(:delete).with(described_class.cache_key(store))
      expect(Rails.cache).to receive(:delete).with("#{described_class.cache_key(store)}:pickup")
      expect(described_class.refresh!(store: store, client: client)).to eq(districts: 2, pickup_cities: 1)
    end

    it "falls back to using districts grouped by city when pickup_cities returns empty" do
      client = instance_double(Sendit::Client)
      allow(client).to receive(:districts).and_return(
        "data" => [
          { "id" => 1, "ville" => "Casablanca", "name" => "Casablanca - Centre", "price" => "25" },
          { "id" => 2, "ville" => "Casablanca", "name" => "Casablanca - Ain Sebaa", "price" => "25" },
          { "id" => 3, "ville" => "Rabat", "name" => "Rabat", "price" => "30" }
        ],
        "last_page" => 1
      )
      allow(client).to receive(:pickup_cities).and_return([])
      allow(Rails.cache).to receive(:delete)
      
      result = described_class.refresh!(store: store, client: client)
      
      expect(result[:districts]).to eq(3)
      expect(result[:pickup_cities]).to eq(2) # Casablanca and Rabat
      
      # Verify the pickup cities are correctly cached
      pickup = described_class.pickup_cities(store: store, client: client)
      expect(pickup.size).to eq(2)
      expect(pickup.map { |p| p[:name] }.sort).to eq(["Casablanca", "Rabat"])
    end

    it "handles pickup_cities API errors gracefully" do
      client = instance_double(Sendit::Client)
      allow(client).to receive(:districts).and_return(
        "data" => [ { "id" => 1, "ville" => "Fès", "name" => "Fès", "price" => "35" } ],
        "last_page" => 1
      )
      allow(client).to receive(:pickup_cities).and_raise(Sendit::Client::Error.new("API error"))
      allow(Rails.cache).to receive(:delete)
      
      expect { described_class.refresh!(store: store, client: client) }.not_to raise_error
      result = described_class.refresh!(store: store, client: client)
      
      expect(result[:districts]).to eq(1)
      expect(result[:pickup_cities]).to eq(0)
    end
  end
end
