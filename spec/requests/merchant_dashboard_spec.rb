require "rails_helper"
require "nokogiri"

RSpec.describe "Merchant dashboard", type: :request do
  let(:password) { "synthetic-password-123" }
  let(:store) { workspace }
  let(:staff) { store.users.create!(email: "dashboard-#{SecureRandom.hex(5)}@example.test", password: password, admin: true) }

  def workspace(**attributes)
    Store.create!({ slug: "dashboard-#{SecureRandom.hex(5)}", name: "Synthetic workspace", currency: "MAD" }.merge(attributes))
  end

  def sign_in(user = staff, workspace: store)
    host! workspace ? "#{workspace.slug}.#{Store.base_domain}" : Store.base_domain
    post "/admin/login", params: { email: user.email, password: password }
    expect(response).to have_http_status(:redirect)
  end

  def document
    Nokogiri::HTML(response.body)
  end

  def order(workspace: store, **attributes)
    customer = workspace.customers.first || workspace.customers.create!(name: "Synthetic buyer", phone: "0612345678", city: "Casablanca")
    workspace.orders.create!({ customer: customer, customer_name: customer.name, customer_phone: customer.phone,
      customer_city: customer.city, customer_address: "Synthetic address", total_cents: 101,
      subtotal_cents: 101, currency: "MAD", status: "new" }.merge(attributes))
  end

  it "requires authentication" do
    host! "#{store.slug}.#{Store.base_domain}"
    get "/admin"
    expect(response).to redirect_to(admin_login_path)
  end

  it "rejects a staff session on another tenant host" do
    sign_in
    foreign = workspace
    host! "#{foreign.slug}.#{Store.base_domain}"
    get "/admin"
    expect(response).to redirect_to(admin_login_path)
  end

  it "redirects platform-only administrators without a workspace to platform administration" do
    platform_user = User.create!(email: "platform-#{SecureRandom.hex(5)}@example.test", password: password, admin: true, super_admin: true)
    sign_in(platform_user, workspace: nil)
    expect(Admin::DashboardSummary).not_to receive(:new)
    get "/admin"
    expect(response).to redirect_to(admin_platform_path)
  end

  %w[fr en ar].each do |locale|
    it "renders #{locale} with appropriate direction and inventory only when local stock is tracked" do
      order(status: "delivered")
      sign_in
      get "/admin", params: { locale: locale }
      expect(response).to have_http_status(:ok)
      expect(document.at_css("html")["dir"]).to eq(locale == "ar" ? "rtl" : "ltr")
      expect(document.at_css('[data-dashboard-mode="storefront"]')).to be_present
      expect(document.at_css("[data-dashboard-storefront]")).to be_present
      expect(document.at_css("[data-dashboard-inventory]")).to be_nil
      expect(response.body).not_to match(/translation missing|translation_missing/i)

      product = store.products.create!(name: "Synthetic product", slug: "synthetic-product", status: "active", price_cents: 101, stock: 0, track_inventory: false)
      get "/admin", params: { locale: locale }
      expect(document.at_css("[data-dashboard-inventory]")).to be_nil
      product.update!(track_inventory: true)
      get "/admin", params: { locale: locale }
      expect(document.at_css("[data-dashboard-inventory]")).to be_present
      expect(response.body).not_to match(/translation missing|translation_missing/i)
    end
  end

  it "renders overview panels with tenant-scoped order and manual campaign data" do
    order(customer_name: "Own pending buyer", total_cents: 12345)
    order(workspace: workspace, customer_name: "Foreign pending buyer")
    account = AdvertisingAccount.create!(store: store, name: "Synthetic reporting", provider: "Meta")
    campaign = account.advertising_campaigns.create!(name: "Own campaign")
    campaign.advertising_performances.create!(date: Time.current.in_time_zone("Africa/Casablanca").to_date,
      spend_cents: 100, delivered_revenue_cents: 500, fulfillment_cost_cents: 150)
    sign_in
    get "/admin", params: { locale: "en" }
    expect(response).to have_http_status(:ok)
    %w[chart statuses pending campaigns].each do |section|
      expect(document.at_css("[data-overview-section='#{section}']")).to be_present
    end
    chart = document.at_css('[data-overview-section="chart"] [data-controller="dashboard-chart"]')
    chart_config = JSON.parse(chart["data-dashboard-chart-config-value"])
    expect(chart_config["type"]).to eq("line")
    expect(chart_config.dig("data", "datasets", 0, "data")).to include(123.45)
    expect(chart["data-dashboard-chart-currency-value"]).to eq("MAD")
    statuses = document.at_css('[data-overview-section="statuses"] [data-controller="dashboard-chart"]')
    expect(JSON.parse(statuses["data-dashboard-chart-config-value"])["type"]).to eq("doughnut")
    expect(response.body).to include("Own pending buyer", "Own campaign")
    expect(response.body).not_to include("Foreign pending buyer")
    expect(document.at_css("a[href='/admin/orders/new']")).to be_present
    expect(document.at_css("a[href='/admin/advertising']")).to be_present
    expect(document.css("form[action*='/outcome']")).to be_empty
  end

  it "offers all three provider presets without publishing an external-only storefront" do
    store.update!(storefront_enabled: false)
    sign_in
    get "/admin", params: { locale: "en" }
    expect(document.at_css('[data-dashboard-mode="connected"]')).to be_present
    expect(document.at_css("[data-dashboard-storefront]")).to be_nil
    %w[shopify woocommerce youcan].each do |provider|
      hrefs = document.css("a[href]").map { |link| link["href"] }
      expect(hrefs).to include(a_string_matching(%r{/admin/store_connections/new\?.*provider=#{provider}}))
    end
    %w[shopify woocommerce youcan].each do |provider|
      get "/admin/store_connections/new", params: { provider: provider }
      expect(response).to have_http_status(:ok)
      expect(document.at_css('input[type="hidden"][name="store_connection[provider]"]')["value"]).to eq(provider)
      expect(document.at_css('nav a[aria-current="page"]')["href"]).to eq(new_admin_store_connection_path(provider: provider))
    end
    get "/en"
    expect(response).to have_http_status(:not_found)
    expect(store.reload).not_to be_storefront_enabled
  end

  it "shows combined setup with honest source health and no secrets or foreign details" do
    source = store.store_connections.create!(provider: "shopify", name: "Synthetic Shopify source",
      external_domain: "synthetic-#{SecureRandom.hex(4)}.myshopify.com", webhook_secret: "synthetic-secret-do-not-render")
    foreign_order = order(workspace: workspace)
    sign_in
    get "/admin", params: { locale: "en" }
    expect(document.at_css('[data-dashboard-mode="combined"]')).to be_present
    row = document.at_css("a[href='/admin/store_connections/#{source.id}']").ancestors("li").first
    expect(row.text).to include(I18n.t("connections.states.awaiting", locale: :en))
    expect(response.body).not_to include(source.webhook_secret, source.token, source.webhook_secret_ciphertext, foreign_order.number)
  end

  it "links callbacks to a queue containing only due active orders for the current workspace" do
    due = order(created_at: 45.days.ago)
    due.create_order_confirmation!(store: store, disposition: "callback", callback_at: 1.minute.ago)
    excluded = [ order, order(archived_at: Time.current), order(status: "delivered"), order(sendit_code: "synthetic-parcel"), order(workspace: workspace) ]
    excluded.each_with_index do |record, index|
      record.create_order_confirmation!(store: record.store, disposition: "callback", callback_at: index.zero? ? 1.day.from_now : 1.minute.ago)
    end
    sign_in
    get "/admin", params: { locale: "en" }
    target = document.at_css('[data-dashboard-work="callbacks"]')["href"]
    expect(target).to include("filter=callbacks_due")
    get target
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(due.number)
    excluded.each { |record| expect(response.body).not_to include(record.number) }
  end
end
