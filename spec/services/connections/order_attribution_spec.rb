# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Meta ad attribution on connected-store orders" do
  let(:suffix) { SecureRandom.hex(5) }
  let(:store) { Store.create!(slug: "attr-#{suffix}", name: "Attribution #{suffix}", currency: "MAD") }
  let(:secret) { "synthetic-webhook-secret-#{suffix}" }
  let(:query) { "utm_source=facebook&utm_campaign=120200000000001&utm_term=120200000000002&utm_content=120200000000003" }
  let(:ids) { { "meta_campaign_id" => "120200000000001", "meta_adset_id" => "120200000000002", "meta_ad_id" => "120200000000003" } }
  let(:address) { { "name" => "Synthetic buyer", "phone" => "0612345678", "city" => "Casablanca", "address1" => "Synthetic address", "country_code" => "MA" } }
  let(:shopify_payload) do
    { "id" => 123, "currency" => "MAD", "financial_status" => "pending", "payment_gateway_names" => [ "Cash on Delivery (COD)" ], "total_tax" => "0.00",
      "total_discounts" => "0.00", "total_price" => "269.90", "shipping_address" => address,
      "total_shipping_price_set" => { "shop_money" => { "amount" => "20.00", "currency_code" => "MAD" } },
      "line_items" => [ { "name" => "External product", "quantity" => 2, "price" => "124.95" } ] }
  end

  def connection(provider, domain)
    store.store_connections.create!(provider: provider, name: provider, external_domain: domain, webhook_secret: secret,
      external_store_id: (provider == "youcan" ? SecureRandom.uuid : nil))
  end

  def deliver_shopify(payload)
    conn = store.store_connections.find_by(provider: "shopify") || connection("shopify", "attr-#{suffix}.myshopify.com")
    body = JSON.generate(payload)
    signature = Base64.strict_encode64(OpenSSL::HMAC.digest("sha256", secret, body))
    Connections::WebhookIntake.new(connection: conn).call(body: body,
      headers: { "X-Shopify-Topic" => "orders/create", "X-Shopify-Shop-Domain" => conn.external_domain, "X-Shopify-Hmac-SHA256" => signature }).receipt.order
  end

  describe "Shopify webhook orders" do
    it "stores the ad ids found in the landing page" do
      order = deliver_shopify(shopify_payload.merge("landing_site" => "/products/x?#{query}"))
      expect(order.attributes.slice(*ids.keys)).to eq(ids)
    end

    it "stores the ad ids found in the note attributes" do
      note = [ { "name" => "utm_source", "value" => "facebook" }, { "name" => "utm_campaign", "value" => "120200000000001" }, { "name" => "utm_term", "value" => "120200000000002" } ]
      order = deliver_shopify(shopify_payload.merge("id" => 124, "note_attributes" => note))
      expect(order.attributes.slice(*ids.keys)).to eq(ids.merge("meta_ad_id" => nil))
    end

    it "leaves the order unattributed without UTM data, with another source, or with unreplaced macros" do
      [ {}, { "landing_site" => "/?utm_source=google&utm_campaign=120200000000001" }, { "landing_site" => "/?utm_source=facebook&utm_campaign=%7B%7Bcampaign.id%7D%7D" },
        { "landing_site" => "/?utm_source=facebook" } ].each_with_index do |extra, index|
        order = deliver_shopify(shopify_payload.merge("id" => 200 + index).merge(extra))
        expect(order.attributes.slice(*ids.keys).values).to all(be_nil), "expected none for #{extra.inspect}"
      end
    end

    it "is part of the order record, scoped to the workspace" do
      order = deliver_shopify(shopify_payload.merge("landing_site" => "/?#{query}"))
      expect(store.orders.where(meta_campaign_id: "120200000000001").pluck(:id)).to eq([ order.id ])
      other = Store.create!(slug: "other-#{suffix}", name: "Other #{suffix}", currency: "MAD")
      expect(other.orders.where(meta_campaign_id: "120200000000001")).to be_empty
    end
  end

  describe "the normalizer for WooCommerce and YouCan orders" do
    let(:woocommerce_payload) do
      { "payment_method" => "cod", "date_paid" => nil, "date_paid_gmt" => nil, "status" => "processing", "currency" => "MAD", "total" => "110.00", "total_tax" => "0.00",
        "discount_total" => "0.00", "shipping_total" => "10.00", "fee_lines" => [], "refunds" => [], "billing" => { "phone" => "0612345678" },
        "shipping" => { "first_name" => "Synthetic", "last_name" => "Buyer", "city" => "Casablanca", "address_1" => "Synthetic address", "country" => "MA" },
        "line_items" => [ { "name" => "Woo product", "quantity" => 1, "total" => "100.00", "subtotal" => "100.00" } ] }
    end
    let(:youcan_payload) do
      { "data" => { "currency" => "MAD", "total" => "110.00", "vat" => "0", "refunds" => [], "payment" => { "gateway_type" => 1, "status_object" => { "slug" => "pending" } },
                    "status_object" => { "slug" => "open" },
                    "shipping" => { "price" => "10.00", "status_object" => { "slug" => "unfulfilled" },
                                    "address" => { "name" => "Synthetic buyer", "phone" => "0612345678", "city" => "Casablanca", "first_line" => "Synthetic address", "country_code" => "MA" } },
                    "variants" => [ { "quantity" => 1, "price" => "100.00", "variant" => { "product" => { "name" => "YouCan product" }, "variations" => {} } } ] } }
    end

    def normalize(provider, payload, domain)
      Connections::OrderNormalizer.new(connection(provider, domain)).call(payload)
    end

    it "adds the ad ids of a WooCommerce order from its order attribution meta data" do
      meta = ids.map { |column, value| { "key" => "_wc_order_attribution_#{{ "meta_campaign_id" => "utm_campaign", "meta_adset_id" => "utm_term", "meta_ad_id" => "utm_content" }[column]}", "value" => value } }
      meta << { "key" => "_wc_order_attribution_utm_source", "value" => "facebook" }
      result = normalize("woocommerce", woocommerce_payload.merge("meta_data" => meta), "woo-#{suffix}.example.test")
      expect(result.slice(*ids.keys.map(&:to_sym))).to eq(meta_campaign_id: "120200000000001", meta_adset_id: "120200000000002", meta_ad_id: "120200000000003")
      expect(result[:total_cents]).to eq(11_000)
    end

    it "does not attribute a WooCommerce order without UTM data" do
      result = normalize("woocommerce", woocommerce_payload, "woo2-#{suffix}.example.test")
      expect(result.keys).not_to include(:meta_campaign_id, :meta_adset_id, :meta_ad_id)
    end

    it "adds the ad ids of a YouCan order when its payload carries them" do
      payload = youcan_payload.deep_merge("data" => { "utm" => { "utm_source" => "facebook", "utm_campaign" => "120200000000001", "utm_term" => "120200000000002", "utm_content" => "120200000000003" } })
      result = normalize("youcan", payload, "youcan-#{suffix}.example.test")
      expect(result.slice(:meta_campaign_id, :meta_adset_id, :meta_ad_id)).to eq(meta_campaign_id: "120200000000001", meta_adset_id: "120200000000002", meta_ad_id: "120200000000003")
    end

    it "does not attribute a YouCan order without UTM data" do
      result = normalize("youcan", youcan_payload, "youcan2-#{suffix}.example.test")
      expect(result.keys).not_to include(:meta_campaign_id)
    end
  end

  describe "the Shopify catch-up poll" do
    it "passes the cart attributes on as note attributes so the same rules apply" do
      node = { "legacyResourceId" => "321", "currencyCode" => "MAD", "totalPriceSet" => { "shopMoney" => { "amount" => "10.00" } }, "lineItems" => { "nodes" => [] },
               "customAttributes" => [ { "key" => "utm_source", "value" => "facebook" }, { "key" => "utm_campaign", "value" => "120200000000001" } ] }
      sync = Connections::ShopifyOrderSync.new(connection("shopify", "poll-#{suffix}.myshopify.com"), api: double("api"))
      payload = sync.send(:order_payload, node)
      expect(payload["note_attributes"]).to eq([ { "name" => "utm_source", "value" => "facebook" }, { "name" => "utm_campaign", "value" => "120200000000001" } ])
      expect(Attribution::Meta.from_payload("shopify", payload)).to eq(meta_campaign_id: "120200000000001")
      expect(sync.send(:order_payload, node.except("customAttributes"))["note_attributes"]).to eq([])
    end
  end
end
