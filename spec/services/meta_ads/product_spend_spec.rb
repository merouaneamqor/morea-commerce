# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Meta Ads product mapping and spend" do
  let(:store) { Store.create!(slug: "meta-prod-#{SecureRandom.hex(5)}", name: "Synthetic", currency: "MAD") }
  let(:connection) { MetaAds::Connection.create!(store: store, access_token: "synthetic-token") }
  let(:account) { MetaAds::AdAccount.create!(store: store, connection: connection, meta_ad_account_id: "act_1", name: "A", currency: "EUR", timezone_name: "UTC", account_status: 1, selected: true) }
  let!(:alpha) { store.products.create!(name: "Chaussure Alpha", slug: "alpha", price_cents: 10_000, status: "active", sku: "ALPHA-01") }
  let!(:beta) { store.products.create!(name: "Sac Beta", slug: "beta", price_cents: 8_000, status: "active", sku: "BETA-02") }
  let(:campaign) { MetaAds::Campaign.create!(store: store, ad_account: account, meta_id: "111", name: "Promo Novembre") }
  let(:ad_set) { MetaAds::AdSet.create!(store: store, ad_account: account, campaign: campaign, meta_id: "222", name: "Casa") }

  def ad(meta_id, name)
    MetaAds::Ad.create!(store: store, ad_account: account, ad_set: ad_set, campaign: campaign, meta_id: meta_id, name: name)
  end

  def insight(ad_record, spend_display, date: Date.new(2026, 11, 3))
    MetaAds::DailyInsight.create!(store: store, ad_account: account, campaign: campaign, ad_set: ad_set, ad: ad_record, level: "ad", date: date, currency: "EUR", spend: 1,
      spend_display: spend_display, display_currency: ("MAD" if spend_display), fx_rate: (10 if spend_display), fx_date: date, synced_at: Time.current,
      meta_campaign_id: "111", meta_adset_id: "222", meta_ad_id: ad_record.meta_id)
  end

  describe MetaAds::ProductMatcher do
    it "links an ad to the one product whose name or SKU it mentions" do
      by_name = ad("301", "Video chaussure alpha - été")
      by_sku = ad("302", "Reel ALPHA-01 v2")
      other = ad("303", "Sac Beta promo")
      expect(described_class.call(store: store)).to eq(3)
      links = MetaAds::ProductLink.where(store: store).to_h { |link| [ link.meta_id, [ link.product_id, link.object_type, link.source ] ] }
      expect(links).to include(by_name.meta_id => [ alpha.id, "ad", "auto" ], by_sku.meta_id => [ alpha.id, "ad", "auto" ], other.meta_id => [ beta.id, "ad", "auto" ])
    end

    it "leaves an ad unlinked when it names two products or none, or only part of a word" do
      ad("311", "Chaussure Alpha et Sac Beta")
      ad("312", "Offre du jour")
      ad("313", "Chaussure Alphabet")
      expect(described_class.call(store: store)).to eq(0)
    end

    it "never replaces an existing link, and is repeatable" do
      linked = ad("321", "Chaussure Alpha")
      MetaAds::ProductLink.create!(store: store, product: beta, object_type: "ad", meta_id: linked.meta_id, source: "manual")
      expect(described_class.call(store: store)).to eq(0)
      expect(MetaAds::ProductLink.find_by!(meta_id: "321")).to have_attributes(product_id: beta.id, source: "manual")
      ad("322", "Sac Beta")
      expect(described_class.call(store: store)).to eq(1)
      expect(described_class.call(store: store)).to eq(0)
    end

    it "links a campaign or ad set by its own name" do
      campaign.update!(name: "Chaussure Alpha - Novembre")
      described_class.call(store: store)
      expect(MetaAds::ProductLink.find_by!(object_type: "campaign", meta_id: "111").product).to eq(alpha)
    end

    it "does not see another store's products" do
      other = Store.create!(slug: "meta-prod-b-#{SecureRandom.hex(5)}", name: "B", currency: "MAD")
      other.products.create!(name: "Montre Gamma", slug: "gamma", price_cents: 100, status: "active")
      ad("331", "Montre Gamma")
      expect(described_class.call(store: store)).to eq(0)
    end
  end

  describe "deleting a store" do
    it "removes its Meta rows, product links and products without tripping over foreign keys" do
      linked = ad("501", "Chaussure Alpha")
      insight(linked, 10)
      MetaAds::ProductLink.create!(store: store, product: alpha, object_type: "ad", meta_id: "501", source: "manual")

      expect { store.destroy! }.to change(Store, :count).by(-1)
      expect([ MetaAds::ProductLink, MetaAds::DailyInsight, MetaAds::Ad, MetaAds::Campaign, MetaAds::AdAccount, MetaAds::Connection ].map(&:count)).to all(eq(0))
    end
  end

  describe MetaAds::ProductSpend do
    it "adds each ad's spend, in the store's currency, to the product linked to the ad, else its ad set, else its campaign" do
      a = ad("401", "x")
      b = ad("402", "y")
      c = ad("403", "z")
      d = ad("404", "w")
      MetaAds::ProductLink.create!(store: store, product: alpha, object_type: "ad", meta_id: "401", source: "manual")
      MetaAds::ProductLink.create!(store: store, product: beta, object_type: "ad_set", meta_id: "222", source: "manual")
      [ [ a, 100 ], [ b, 50 ], [ c, 25 ] ].each { |record, spend| insight(record, spend) }
      insight(d, 10, date: Date.new(2026, 11, 4))

      result = described_class.call(store: store, range: Date.new(2026, 11, 1)..Date.new(2026, 11, 30))
      expect(result.by_product).to eq(alpha.id => 100, beta.id => 85)
      expect(result.unassigned).to eq(0)
      expect(result.currency).to eq("MAD")

      MetaAds::ProductLink.where(object_type: "ad_set").destroy_all
      result = described_class.call(store: store, range: Date.new(2026, 11, 1)..Date.new(2026, 11, 3))
      expect(result.by_product).to eq(alpha.id => 100)
      expect(result.unassigned).to eq(75)
    end

    it "reports rows without a conversion instead of counting them, and ignores other levels and days" do
      a = ad("411", "x")
      insight(a, nil)
      insight(a, 40, date: Date.new(2026, 11, 2))
      MetaAds::DailyInsight.create!(store: store, ad_account: account, campaign: campaign, level: "campaign", date: Date.new(2026, 11, 3), currency: "EUR", spend: 999,
        spend_display: 9990, display_currency: "MAD", fx_rate: 10, fx_date: Date.new(2026, 11, 3), synced_at: Time.current, meta_campaign_id: "111")
      result = described_class.call(store: store, range: Date.new(2026, 11, 1)..Date.new(2026, 11, 3))
      expect(result.unassigned).to eq(40)
      expect(result.unconverted_rows).to eq(1)
    end
  end
end
