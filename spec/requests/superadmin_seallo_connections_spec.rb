require "rails_helper"
require "nokogiri"

RSpec.describe "Superadmin Seallo connections", type: :request do
  let(:password) { "Synthetic-support-password-123!" }
  let!(:store) { Store.create!(slug: "support-#{SecureRandom.hex(5)}", name: "Synthetic support workspace", currency: "MAD") }
  let!(:actor) { User.create!(email: "support-#{SecureRandom.hex(5)}@example.test", password: password, admin: true, super_admin: true) }
  let!(:connection) do
    store.store_connections.create!(provider: "shopify", name: "Synthetic connection", external_domain: "support.myshopify.com",
      shopify_app: "seallo_connect", shopify_oauth: true, shopify_sync_error: "private-provider-response",
      shopify_api_error_code: "invalid_response")
  end
  let!(:authorization) do
    SealloConnectionCode.create!(store: store, user: actor, digest: "synthetic-private-digest",
      shop_domain: "pending.myshopify.com", expires_at: 10.minutes.from_now)
  end
  let(:path) { "/superadmin/seallo_connections" }

  before do
    host! Store.base_domain
    allow(Connections::SealloBridge).to receive(:entitlement).and_raise("Unexpected provider request")
    allow(Connections::SealloBridge).to receive(:graphql).and_raise("Unexpected provider request")
  end

  def sign_in(user = actor)
    post "/admin/login", params: { email: user.email, password: password }
    expect(response).to have_http_status(:redirect)
  end

  it "requires authentication for the page and actions" do
    get path
    expect(response).to redirect_to(admin_login_path)
    post "#{path}/recheck", params: { connection_id: connection.id }
    expect(response).to redirect_to(admin_login_path)
    post "#{path}/diagnose_link", params: { authorization_id: authorization.id }
    expect(response).to redirect_to(admin_login_path)
  end

  it "rejects merchant administrators before any cross-workspace operation" do
    merchant = store.users.create!(email: "merchant-#{SecureRandom.hex(5)}@example.test", password: password, admin: true)
    host! "#{store.slug}.#{Store.base_domain}"
    sign_in(merchant)
    [ [ :get, path, {} ], [ :post, "#{path}/recheck", { connection_id: connection.id } ],
      [ :post, "#{path}/diagnose_link", { authorization_id: authorization.id } ] ].each do |method, url, params|
      public_send(method, url, params: params)
      expect(response).to redirect_to(admin_root_path)
    end
    expect(Connections::SealloBridge).not_to have_received(:entitlement)
  end

  it "shows safe cross-workspace diagnostics without contacting providers" do
    other = Store.create!(slug: "other-#{SecureRandom.hex(5)}", name: "Other support workspace", storefront_enabled: false)
    other.store_connections.create!(provider: "shopify", name: "Other synthetic connection", external_domain: "other.myshopify.com",
      shopify_app: "seallo_connect", shopify_oauth: true)
    sign_in
    get path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(other.name, "support.myshopify.com", "pending.myshopify.com", "Recheck connection", "Check link")
    expect(response.body).not_to include("private-provider-response", authorization.digest)
    expect(Connections::SealloBridge).not_to have_received(:entitlement)
    expect(Connections::SealloBridge).not_to have_received(:graphql)
    document = Nokogiri::HTML(response.body)
    expect(document.css(".seallo-diagnostics__scroll[tabindex='0']").length).to eq(2)
    expect(document.at_css("form[action='#{path}/recheck']")["method"]).to eq("post")
  end

  it "filters both lists using a literal shop search" do
    sign_in
    get path, params: { q: "pending.myshopify.com" }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("No matching Seallo connections.", "pending.myshopify.com")
    get path, params: { q: "%" }
    expect(response.body).to include("No matching Seallo connections.", "No matching pending authorizations")
  end

  it "bounds connection rows and offers pagination" do
    26.times do |index|
      store.store_connections.create!(provider: "shopify", name: "Paged connection #{index}",
        external_domain: "paged-#{index}.myshopify.com", shopify_app: "seallo_connect", shopify_oauth: true)
    end
    sign_in
    get path
    document = Nokogiri::HTML(response.body)
    expect(document.css("[aria-label='Seallo connections'] tbody tr").length).to eq(25)
    expect(document.at_css(".seallo-diagnostics__pagination").text).to include("Next")
    get path, params: { page: 2 }
    document = Nokogiri::HTML(response.body)
    expect(document.css("[aria-label='Seallo connections'] tbody tr").length).to eq(2)
    expect(document.at_css(".seallo-diagnostics__pagination").text).to include("Previous")
  end

  it "refreshes active billing and checks access without importing orders" do
    allow(Connections::SealloBridge).to receive(:entitlement).with(shop: connection.external_domain).and_return(
      "active" => true, "plan_name" => "Seallo Basic", "order_limit" => 30,
      "current_period_start" => 1.day.ago.iso8601, "current_period_end" => nil)
    api = instance_double(Connections::ShopifyApi, verify!: true)
    allow(Connections::ShopifyApi).to receive(:new).and_return(api)
    sign_in
    expect do
      post "#{path}/recheck", params: { connection_id: connection.id }
    end.not_to change { ActiveJob::Base.queue_adapter.enqueued_jobs.size }
    expect(response).to redirect_to(path)
    follow_redirect!
    expect(response.body).to include("connection and Shopify order access are verified")
    expect(connection.reload.shopify_order_limit).to eq(30)
    expect(api).to have_received(:verify!)
  end

  it "keeps disconnected stores inactive when the administrator rechecks" do
    connection.update!(active: false)
    sign_in
    post "#{path}/recheck", params: { connection_id: connection.id }
    expect(response).to redirect_to(path)
    follow_redirect!
    expect(response.body).to include("merchant must approve reconnection")
    expect(connection.reload).not_to be_active
    expect(Connections::SealloBridge).not_to have_received(:entitlement)
  end

  it "checks a pending plan without linking or consuming the merchant authorization" do
    allow(Connections::SealloBridge).to receive(:entitlement).with(shop: authorization.shop_domain).and_return(
      "active" => true, "plan_name" => "Seallo Pro", "order_limit" => 100,
      "current_period_start" => 1.day.ago.iso8601, "current_period_end" => nil)
    sign_in
    expect do
      post "#{path}/diagnose_link", params: { authorization_id: authorization.id }
    end.not_to change(StoreConnection, :count)
    expect(response).to redirect_to(path)
    follow_redirect!
    expect(response.body).to include("Shopify returned a valid plan")
    expect(authorization.reload.consumed_at).to be_nil
  end

  it "returns curated errors without exposing upstream responses" do
    allow(Connections::SealloBridge).to receive(:entitlement).and_raise(Connections::SealloBridge::Error, "private-upstream-secret")
    sign_in
    post "#{path}/recheck", params: { connection_id: connection.id }
    follow_redirect!
    expect(response.body).to include("Check the deployed bridge and plan contract")
    expect(response.body).not_to include("private-upstream-secret")
  end

  it "does not allow another provider to be checked through a submitted id" do
    connection.update!(shopify_app: nil)
    sign_in
    post "#{path}/recheck", params: { connection_id: connection.id }
    expect(response).to have_http_status(:not_found)
    expect(Connections::SealloBridge).not_to have_received(:entitlement)
  end

  it "invalidates suspended superadmin sessions" do
    sign_in
    actor.update!(status: "suspended")
    get path
    expect(response).to redirect_to(admin_login_path)
  end
end
