# frozen_string_literal: true

require "rails_helper"

RSpec.describe Connections::ShopifyOrderSync do
  let(:app_secret) { "synthetic-shared-client-secret" }
  let(:now) { Time.utc(2026, 10, 26, 12) }
  let(:store) { Store.create!(slug: "shopify-sync-#{SecureRandom.hex(5)}", name: "Synthetic workspace", currency: "MAD", storefront_enabled: false) }
  let(:connection) do
    store.store_connections.create!(name: "Shopify API", provider: "shopify", shopify_oauth: true,
      external_domain: "synthetic-#{SecureRandom.hex(5)}.myshopify.com")
  end

  # Replays queued GraphQL data and records each call.
  let(:api) do
    Class.new do
      attr_reader :calls

      def initialize(responses) = (@responses = responses; @calls = [])

      def graphql(query:, variables: {})
        @calls << [ query, variables ]
        @responses.shift || raise("Unexpected GraphQL call")
      end
    end
  end

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("SHOPIFY_CLIENT_SECRET").and_return(app_secret)
  end

  def node(id: "1001", payment: "PENDING", gateways: [ "Cash on Delivery (COD)" ], created_at: "2026-10-26T10:00:00Z")
    money = ->(amount) { { "shopMoney" => { "amount" => amount } } }
    {
      "legacyResourceId" => id, "createdAt" => created_at, "currencyCode" => "MAD", "phone" => nil, "cancelledAt" => nil,
      "displayFinancialStatus" => payment, "displayFulfillmentStatus" => "UNFULFILLED", "paymentGatewayNames" => gateways,
      "totalPriceSet" => money.call("230.00"), "totalTaxSet" => money.call("0.00"), "totalDiscountsSet" => money.call("0.00"),
      "totalShippingPriceSet" => money.call("30.00"),
      "shippingAddress" => { "name" => "Synthetic Buyer", "phone" => "0612345678", "city" => "Casablanca",
        "address1" => "12 Synthetic street", "address2" => "Maarif", "countryCodeV2" => "MA" },
      "lineItems" => { "nodes" => [ { "name" => "Synthetic tee", "quantity" => 2, "variantTitle" => "M / Sand", "requiresShipping" => true,
        "unfulfilledQuantity" => 2, "originalUnitPriceSet" => money.call("100.00"), "totalDiscountSet" => money.call("0.00") } ] }
    }
  end

  def orders_page(*nodes, next_page: false)
    { "orders" => { "pageInfo" => { "hasNextPage" => next_page, "endCursor" => "cursor" }, "nodes" => nodes } }
  end

  def sync(*responses)
    fake = api.new(responses)
    [ described_class.new(connection, api: fake, now: now), fake ]
  end

  it "imports a COD order once and does not duplicate it on the next run" do
    first, = sync(orders_page(node))
    result = first.poll!
    expect(result).to have_attributes(imported: 1, rejected: 0, replayed: 0, complete: true)
    order = store.orders.sole
    expect(order).to have_attributes(customer_name: "Synthetic Buyer", customer_city: "Casablanca", status: "new",
      payment_method: "cod", total_cents: 23_000, shipping_cents: 3_000, currency: "MAD")
    expect(order.order_items.sole).to have_attributes(product_name: "Synthetic tee", variant_name: "M / Sand", quantity: 2, unit_price_cents: 10_000)
    expect(connection.reload.shopify_orders_synced_at).to eq(now)

    second, = sync(orders_page(node))
    expect(second.poll!).to have_attributes(imported: 0, replayed: 1)
    expect(store.orders.count).to eq(1)
  end

  it "keeps a rejected receipt instead of importing orders that are not unpaid COD" do
    sync_run, = sync(orders_page(node(id: "2002", payment: "PAID", gateways: [ "shopify_payments" ])))
    expect(sync_run.poll!).to have_attributes(imported: 0, rejected: 1)
    expect(store.orders.count).to eq(0)
    expect(connection.external_order_receipts.sole).to have_attributes(external_id: "2002", status: "rejected", error_code: "unsupported_payment")
  end

  it "resumes from the last handled order when the page limit is reached" do
    stub_const("Connections::ShopifyOrderSync::MAX_PAGES", 1)
    run, = sync(orders_page(node, next_page: true))
    expect(run.poll!.complete).to be(false)
    expect(connection.reload.shopify_orders_synced_at).to eq(Time.utc(2026, 10, 26, 10))
  end

  it "registers the order webhook once and rechecks at most daily" do
    url = described_class.webhook_url(connection)
    run, fake = sync({ "webhookSubscriptions" => { "nodes" => [] } },
      { "webhookSubscriptionCreate" => { "webhookSubscription" => { "id" => "gid://1" }, "userErrors" => [] } })
    run.ensure_webhook!
    expect(fake.calls.last.last).to eq(url: url)
    expect(url).to end_with("/webhooks/store_orders/#{connection.token}")
    expect(connection.reload.shopify_webhook_checked_at).to eq(now)

    again, again_api = sync
    again.ensure_webhook!
    expect(again_api.calls).to be_empty

    later = described_class.new(connection, now: now + 2.days, api: api.new([ { "webhookSubscriptions" => { "nodes" =>
      [ { "id" => "gid://1", "endpoint" => { "callbackUrl" => url } } ] } } ]))
    expect { later.ensure_webhook! }.not_to raise_error
  end

  it "accepts webhooks signed with the shared app secret and rejects any other signature" do
    payload = JSON.generate(described_class.new(connection, api: api.new([]), now: now).order_payload(node(id: "3003")))
    signed = ->(secret) { Base64.strict_encode64(OpenSSL::HMAC.digest("sha256", secret, payload)) }
    headers = ->(signature) { { "X-Shopify-Hmac-SHA256" => signature, "X-Shopify-Topic" => "orders/create", "X-Shopify-Shop-Domain" => connection.external_domain } }

    expect { Connections::WebhookIntake.new(connection: connection).call(body: payload, headers: headers.call(signed.call("wrong-secret"))) }
      .to raise_error(Connections::WebhookIntake::Error) { |error| expect(error.status).to eq(401) }
    result = Connections::WebhookIntake.new(connection: connection).call(body: payload, headers: headers.call(signed.call(app_secret)))
    expect(result.receipt.status).to eq("accepted")
    expect(store.orders.count).to eq(1)
  end
end
