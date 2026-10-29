# frozen_string_literal: true

require "rails_helper"
require "nokogiri"

RSpec.describe "Manual Shopify order synchronization", type: :request do
  let(:password) { "synthetic-manual-sync-password" }
  let(:store) { Store.create!(slug: "manual-sync-#{SecureRandom.hex(5)}", name: "Synthetic sync workspace", currency: "MAD", storefront_enabled: false) }
  let(:staff) { store.users.create!(email: "manual-sync-#{SecureRandom.hex(5)}@example.test", password: password, admin: true) }
  let(:connection) { create_connection(store) }

  before do
    host! Store.base_domain
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("SHOPIFY_CLIENT_ID").and_return("synthetic-client-id")
    allow(ENV).to receive(:[]).with("SHOPIFY_CLIENT_SECRET").and_return("synthetic-client-secret")
    expect(Connections::ShopifyApi).not_to receive(:new)
  end

  def create_connection(workspace, **overrides)
    workspace.store_connections.create!({ name: "Synthetic Shopify #{SecureRandom.hex(4)}", provider: "shopify", external_domain: "manual-#{SecureRandom.hex(5)}.myshopify.com", shopify_oauth: true, shopify_refresh_token: "synthetic-refresh-token", shopify_refresh_token_expires_at: 30.days.from_now }.merge(overrides))
  end

  def sign_in(user = staff)
    post "/admin/login", params: { email: user.email, password: password }
  end

  def document
    Nokogiri::HTML(response.body)
  end

  def sync_jobs
    enqueued_jobs.select { |job| job[:job] == ShopifyOrdersSyncJob }
  end

  it "queues only this workspace's active OAuth connections and never calls providers during the request" do
    first = connection
    second = create_connection(store)
    create_connection(store, active: false)
    create_connection(store, shopify_refresh_token: nil)
    other = Store.create!(slug: "sync-other-#{SecureRandom.hex(5)}", name: "Other workspace", currency: "MAD")
    foreign = create_connection(other)
    sign_in
    expect { post "/admin/orders/shopify_sync_all", params: { store_id: other.id, connection_id: foreign.id } }.not_to change(Order, :count)
    expect(response).to redirect_to("/admin/orders")
    expect(response).to have_http_status(:see_other)
    expect(sync_jobs.map { |job| job[:args] }).to match_array([ [ first.id ], [ second.id ] ])
    expect(flash[:notice]).to be_present
  end

  it "queues a single scoped connection and tolerates repeated requests without writing orders" do
    connection
    create_connection(store)
    sign_in
    expect do
      2.times do
        patch "/admin/store_connections/#{connection.id}", params: { operation: "sync_shopify_orders" }
        expect(response).to redirect_to("/admin/store_connections/#{connection.id}")
      end
    end.not_to change(Order, :count)
    expect(sync_jobs.map { |job| job[:args] }).to eq([ [ connection.id ], [ connection.id ] ])
  end

  it "rejects a foreign connection without queuing work" do
    other = Store.create!(slug: "sync-foreign-#{SecureRandom.hex(5)}", name: "Other workspace", currency: "MAD")
    foreign = create_connection(other)
    sign_in
    patch "/admin/store_connections/#{foreign.id}", params: { operation: "sync_shopify_orders" }
    expect(response).to have_http_status(:not_found)
    expect(sync_jobs).to be_empty
  end

  it "reports disconnected and credentialless sources instead of claiming to sync" do
    connection.update!(active: false)
    sign_in
    post "/admin/orders/shopify_sync_all"
    expect(response).to have_http_status(:see_other)
    expect(flash[:alert]).to be_present
    patch "/admin/store_connections/#{connection.id}", params: { operation: "sync_shopify_orders" }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(document.at_css("[role='alert']")).to be_present
    expect(sync_jobs).to be_empty
  end

  it "does not synchronize another provider" do
    woo = store.store_connections.create!(provider: "woocommerce", name: "Woo synthetic", external_domain: "synthetic.example.test", webhook_secret: "synthetic-webhook-secret")
    sign_in
    patch "/admin/store_connections/#{woo.id}", params: { operation: "sync_shopify_orders" }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(sync_jobs).to be_empty
  end

  it "renders POST forms, progress, connection links and localized labels including Arabic RTL" do
    connection.update!(shopify_orders_synced_at: Time.utc(2026, 10, 29, 10, 30), last_error_code: "unsupported_payment")
    sign_in
    %w[fr en ar].each do |locale|
      get "/admin/orders", params: { locale: locale }
      expect(response).to have_http_status(:ok)
      expect(document.at_css("html")["dir"]).to eq(locale == "ar" ? "rtl" : "ltr")
      form = document.at_css("form[action='/admin/orders/shopify_sync_all']")
      expect(form["method"]).to eq("post")
      expect(document.at_css("#shopify-sync-title")).to be_present
      expect(document.at_css("time[datetime='2026-10-29T10:30:00Z']")).to be_present
      expect(document.at_css(".translation_missing")).to be_nil
      expect(response.body).not_to include("synthetic-refresh-token", "synthetic-client-secret")
      get "/admin/store_connections/#{connection.id}", params: { locale: locale }
      expect(response).to have_http_status(:ok)
      operation = document.at_css("input[name='operation'][value='sync_shopify_orders']")
      expect(operation.ancestors("form").first["method"]).to eq("post")
      expect(document.at_css(".translation_missing")).to be_nil
    end
  end

  it "hides the Orders-page action when this workspace has no Shopify OAuth source" do
    sign_in
    get "/admin/orders"
    expect(response).to have_http_status(:ok)
    expect(document.at_css("form[action='/admin/orders/shopify_sync_all']")).to be_nil
  end

  it "disables the action and rejects the request when the shared app is not configured" do
    connection
    sign_in
    allow(ENV).to receive(:[]).with("SHOPIFY_CLIENT_ID").and_return(nil)
    get "/admin/orders"
    expect(document.at_css("form[action='/admin/orders/shopify_sync_all'] button[disabled]")).to be_present
    post "/admin/orders/shopify_sync_all"
    expect(response).to have_http_status(:see_other)
    expect(flash[:alert]).to be_present
    expect(sync_jobs).to be_empty
  end

  it "requires authentication and rejects a GET without queuing work" do
    post "/admin/orders/shopify_sync_all"
    expect(response).to redirect_to("/admin/login")
    sign_in
    get "/admin/orders/shopify_sync_all"
    expect(response).to have_http_status(:not_found)
    expect(sync_jobs).to be_empty
  end

  it "rejects platform-only sessions without a selected workspace" do
    root = User.create!(email: "sync-platform-#{SecureRandom.hex(5)}@example.test", password: password, admin: true, super_admin: true)
    sign_in(root)
    post "/admin/orders/shopify_sync_all"
    expect(response).to have_http_status(:not_found)
    expect(sync_jobs).to be_empty
  end

  it "requires subscription access and denies confirmation agents" do
    connection
    sign_in
    store.update!(subscription_required: true, billing_status: "past_due")
    post "/admin/orders/shopify_sync_all"
    expect(response).to redirect_to("/admin/subscription")
    agent = store.users.create!(email: "sync-agent-#{SecureRandom.hex(5)}@example.test", password: password, confirmation_role: "agent")
    sign_in(agent)
    post "/admin/orders/shopify_sync_all"
    expect(response).to redirect_to("/admin/confirmations/home")
    expect(sync_jobs).to be_empty
  end

  it "protects the action with CSRF and accepts the rendered form token" do
    connection
    sign_in
    old = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    post "/admin/orders/shopify_sync_all"
    expect(response).to have_http_status(:unprocessable_entity)
    expect(sync_jobs).to be_empty
    get "/admin/orders"
    form = document.at_css("form[action='/admin/orders/shopify_sync_all']")
    token = form.at_css("input[name='authenticity_token']")["value"]
    post "/admin/orders/shopify_sync_all", params: { authenticity_token: token }
    expect(response).to have_http_status(:see_other)
    expect(sync_jobs.size).to eq(1)
  ensure
    ActionController::Base.allow_forgery_protection = old
  end
end
