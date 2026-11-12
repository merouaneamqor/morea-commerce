require "rails_helper"
require "nokogiri"

RSpec.describe "Platform dashboard", type: :request do
  let(:password) { "synthetic-platform-password-123" }
  let!(:store) { Store.create!(slug: "pd-#{SecureRandom.hex(5)}", name: "Synthetic workspace", currency: "MAD") }
  let!(:owner) { User.create!(email: "platform-#{SecureRandom.hex(5)}@example.test", password: password, super_admin: true, admin: true) }

  before { host! Store.base_domain }

  def sign_in(user)
    post "/admin/login", params: { email: user.email, password: password }
  end

  def add_order(currency, cents, status = "new")
    customer = store.customers.first || store.customers.create!(name: "Synthetic buyer", phone: "0612345678", city: "Casablanca")
    store.orders.create!(customer: customer, customer_name: customer.name, customer_phone: customer.phone,
      customer_city: customer.city, customer_address: "Synthetic address", currency: currency,
      subtotal_cents: cents, total_cents: cents, status: status)
  end

  it "requires authentication and rejects merchant administrators" do
    get "/admin/platform"
    expect(response).to redirect_to(admin_login_path)
    merchant = store.users.create!(email: "merchant-#{SecureRandom.hex(5)}@example.test", password: password, admin: true)
    sign_in(merchant)
    get "/admin/platform"
    expect(response).to redirect_to(admin_root_path)
  end

  it "shows a zero value when there are no orders" do
    sign_in(owner)
    get "/admin/platform"
    expect(response).to have_http_status(:ok)
    value = Nokogiri::HTML(response.body).at_css('[data-platform-order-value="MAD"]')
    expect(value.text.strip).to eq(ApplicationController.helpers.dashboard_money(0, "MAD"))
  end

  %w[fr en ar].each do |locale|
    it "keeps currencies and cents separate in #{locale}" do
      add_order("MAD", 12345)
      add_order("DH", 101)
      add_order("EUR", 6789)
      add_order("EUR", 99900, "cancelled")
      sign_in(owner)
      get "/admin/platform", params: { locale: locale }
      expect(response).to have_http_status(:ok)
      document = Nokogiri::HTML(response.body)
      expect(document.at_css("html")["dir"]).to eq(locale == "ar" ? "rtl" : "ltr")
      values = document.css("[data-platform-order-value]").index_by { |node| node["data-platform-order-value"] }
      expect(values.keys).to contain_exactly("MAD", "EUR")
      expect(values.fetch("MAD").text.strip).to eq(ApplicationController.helpers.dashboard_money(12446, "MAD"))
      expect(values.fetch("EUR").text.strip).to eq(ApplicationController.helpers.dashboard_money(6789, "EUR"))
      expect(response.body).not_to match(/translation missing|translation_missing/i)
    end
  end

  it "renders the action queue with deep links and keeps the workspaces list" do
    travel_to Time.find_zone!("Africa/Casablanca").local(2026, 11, 12, 12) do
      invoice = store.invoices.create!(
        period_starts_on: Date.current.beginning_of_month,
        period_ends_on: Date.current.end_of_month,
        billing_interval: "monthly",
        status: "issued",
        due_on: Date.current - 3,
        amount_cents: 5000,
        issued_at: Time.current
      )
      access_request = AccessRequest.create!(
        store_name: "Queue Merchant #{SecureRandom.hex(3)}",
        email: "queue-#{SecureRandom.hex(5)}@example.test",
        locale: "en",
        storefront_enabled: false
      )
      connection = store.store_connections.create!(
        provider: "shopify",
        name: "Synthetic failing shop",
        external_domain: "fail-#{SecureRandom.hex(4)}.myshopify.com",
        shopify_oauth: true,
        shopify_app: "seallo_connect",
        active: true,
        shopify_api_error_code: "unavailable"
      )
      privacy = PlatformPrivacyRightsRequest.create!(
        request_type: "access",
        status: "open",
        requester_name: "Synthetic requester",
        requester_contact: "privacy-#{SecureRandom.hex(4)}@example.test"
      )

      sign_in(owner)
      get "/admin/platform"
      expect(response).to have_http_status(:ok)

      document = Nokogiri::HTML(response.body)
      queue = document.at_css("#action-queue")
      expect(queue).to be_present
      expect(queue.at_css("a[href='#{admin_tenant_invoice_path(store, invoice)}']")).to be_present
      expect(queue.at_css("a[href='#{admin_access_requests_path(status: "pending")}']")).to be_present
      expect(queue.at_css("a[href='#{admin_platform_integration_path(store)}']")).to be_present
      expect(queue.at_css("a[href='#{admin_platform_privacy_rights_request_path(privacy)}']")).to be_present
      expect(queue.text).to include(access_request.store_name)
      expect(queue.text).to include(connection.external_domain)

      workspaces = document.at_css("#workspaces")
      expect(workspaces).to be_present
      expect(workspaces.at_css("a[href='#{admin_tenant_path(store)}']").text).to include(store.name)
      expect(response.body).not_to match(/translation missing|translation_missing/i)
    end
  end
end
