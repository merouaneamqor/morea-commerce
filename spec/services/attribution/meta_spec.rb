# frozen_string_literal: true

require "rails_helper"

RSpec.describe Attribution::Meta do
  let(:ids) { { meta_campaign_id: "120200000000001", meta_adset_id: "120200000000002", meta_ad_id: "120200000000003" } }
  let(:query) { "utm_source=facebook&utm_campaign=120200000000001&utm_term=120200000000002&utm_content=120200000000003" }

  describe ".from_params" do
    it "reads campaign, ad set and ad ids when the source is facebook" do
      expect(described_class.from_params("utm_source" => "facebook", "utm_campaign" => "120200000000001", "utm_term" => "120200000000002", "utm_content" => "120200000000003")).to eq(ids)
    end

    it "accepts symbol keys, different case and surrounding spaces" do
      expect(described_class.from_params(UTM_SOURCE: " Facebook ", utm_campaign: " 120200000000001 ")).to eq(meta_campaign_id: "120200000000001")
    end

    it "keeps only the campaign when the ad set and ad are missing or invalid" do
      params = { "utm_source" => "facebook", "utm_campaign" => "120200000000001", "utm_term" => "{{adset.id}}", "utm_content" => "summer-ad" }
      expect(described_class.from_params(params)).to eq(meta_campaign_id: "120200000000001")
    end

    it "never attributes an order from another source or without a real campaign id" do
      base = { "utm_campaign" => "120200000000001", "utm_term" => "120200000000002", "utm_content" => "120200000000003" }
      [ {}, base, base.merge("utm_source" => "google"), base.merge("utm_source" => "instagram"), base.merge("utm_source" => ""),
        { "utm_source" => "facebook" }, { "utm_source" => "facebook", "utm_campaign" => "{{campaign.id}}" },
        { "utm_source" => "facebook", "utm_campaign" => "my-campaign", "utm_term" => "120200000000002" },
        { "utm_source" => "facebook", "utm_campaign" => "123", "utm_term" => "120200000000002" },
        { "utm_source" => "facebook", "utm_campaign" => "1" * 26 },
        { "utm_source" => "facebook", "utm_term" => "120200000000002", "utm_content" => "120200000000003" },
        { "utm_source" => "facebook", "utm_campaign" => [ "120200000000001" ] }, nil, "text" ].each do |params|
        expect(described_class.from_params(params)).to eq({}), "expected no attribution for #{params.inspect}"
      end
    end
  end

  describe ".from_url" do
    it "reads a landing page URL, a path with a query, or a bare query string" do
      expect(described_class.from_params(described_class.from_url("https://shop.example.test/products/x?#{query}"))).to eq(ids)
      expect(described_class.from_params(described_class.from_url("/?#{query}#section"))).to eq(ids)
      expect(described_class.from_params(described_class.from_url(query))).to eq(ids)
    end

    it "copes with malformed, empty and oversized input" do
      [ nil, "", "https://shop.example.test/", "?", "%%%%", "a=b&&&=", "x?utm_source[]=facebook", "?" + ("a=b&" * 3_000) ].each do |url|
        expect { described_class.from_url(url) }.not_to raise_error
      end
      expect(described_class.from_params(described_class.from_url("?utm_source[]=facebook&utm_campaign=120200000000001"))).to eq({})
    end
  end

  describe ".from_payload" do
    it "reads a Shopify order from its landing page, its note attributes, or the UTM data of the visit" do
      expect(described_class.from_payload("shopify", { "landing_site" => "/products/x?#{query}" })).to eq(ids)
      note = [ { "name" => "utm_source", "value" => "facebook" }, { "name" => "utm_campaign", "value" => "120200000000001" }, { "name" => "utm_content", "value" => "120200000000003" } ]
      expect(described_class.from_payload("shopify", { "note_attributes" => note })).to eq(meta_campaign_id: "120200000000001", meta_ad_id: "120200000000003")
      expect(described_class.from_payload("shopify", { "utm" => { "utm_source" => "facebook", "utm_campaign" => "120200000000001" } })).to eq(meta_campaign_id: "120200000000001")
    end

    it "prefers note attributes over the landing page and falls through when the first source holds no usable value" do
      note = [ { "name" => "utm_source", "value" => "facebook" }, { "name" => "utm_campaign", "value" => "120200000000009" } ]
      expect(described_class.from_payload("shopify", { "note_attributes" => note, "landing_site" => "/?#{query}" })).to eq(meta_campaign_id: "120200000000009")
      bad_note = [ { "name" => "utm_source", "value" => "facebook" }, { "name" => "utm_campaign", "value" => "{{campaign.id}}" } ]
      expect(described_class.from_payload("shopify", { "note_attributes" => bad_note, "landing_site" => "/?#{query}" })).to eq(ids)
    end

    it "reads a WooCommerce order from its order attribution meta data and the session entry URL" do
      meta = [ { "key" => "_wc_order_attribution_utm_source", "value" => "facebook" }, { "key" => "_wc_order_attribution_utm_campaign", "value" => "120200000000001" },
               { "key" => "_wc_order_attribution_utm_term", "value" => "120200000000002" }, { "key" => "_wc_order_attribution_utm_content", "value" => "120200000000003" } ]
      expect(described_class.from_payload("woocommerce", { "meta_data" => meta })).to eq(ids)
      entry = [ { "key" => "_wc_order_attribution_session_entry", "value" => "https://shop.example.test/?#{query}" } ]
      expect(described_class.from_payload("woocommerce", { "meta_data" => entry })).to eq(ids)
    end

    it "reads a YouCan order wherever UTM data is carried, and never invents one" do
      expect(described_class.from_payload("youcan", { "utm_source" => "facebook", "utm_campaign" => "120200000000001" })).to eq(meta_campaign_id: "120200000000001")
      expect(described_class.from_payload("youcan", { "metadata" => { "utm_source" => "facebook", "utm_campaign" => "120200000000001", "utm_content" => "120200000000003" } }))
        .to eq(meta_campaign_id: "120200000000001", meta_ad_id: "120200000000003")
      expect(described_class.from_payload("youcan", { "landing_url" => "https://shop.example.test/?#{query}" })).to eq(ids)
      expect(described_class.from_payload("youcan", { "id" => 1, "total" => "10" })).to eq({})
    end

    it "returns nothing for payloads without attribution or of the wrong shape" do
      [ "shopify", "woocommerce", "youcan" ].each do |provider|
        expect(described_class.from_payload(provider, {})).to eq({})
        expect(described_class.from_payload(provider, nil)).to eq({})
        expect(described_class.from_payload(provider, { "note_attributes" => "x", "meta_data" => { "a" => 1 }, "utm" => "x", "landing_site" => 12 })).to eq({})
      end
    end
  end
end
