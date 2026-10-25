require "rails_helper"

RSpec.describe "Delivery dashboard", type: :request do
  let(:password) { "synthetic-password-123" }
  let(:store) { Store.create!(slug: "delivery-#{SecureRandom.hex(5)}", name: "Synthetic workspace") }
  let(:staff) { store.users.create!(email: "delivery-#{SecureRandom.hex(5)}@example.test", password: password, admin: true) }

  def sign_in
    host! "#{store.slug}.#{Store.base_domain}"
    post "/admin/login", params: { email: staff.email, password: password }
  end

  it "requires authentication" do
    host! "#{store.slug}.#{Store.base_domain}"
    get "/admin/delivery"
    expect(response).to redirect_to(admin_login_path)
  end

  it "renders usable filters and honest empty state without making provider calls" do
    sign_in
    expect(Sendit::Sync).not_to receive(:new)
    get "/admin/delivery", params: { locale: "en", start_date: "invalid", q: "<script>" }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("No shipments match these filters.", "Not configured", "Shipment status breakdown")
    expect(response.body).to include("&lt;script&gt;")
    expect(response.body).not_to include('value="<script>"')
  end

  it "renders only shipments from the authenticated workspace" do
    foreign = Store.create!(slug: "foreign-shipment-#{SecureRandom.hex(5)}", name: "Synthetic foreign workspace")
    [ [ store, "OWN-TRACKING", "Own synthetic buyer" ], [ foreign, "FOREIGN-TRACKING", "Foreign synthetic buyer" ] ].each do |workspace, tracking, name|
      customer = workspace.customers.create!(name: name, phone: "0612345678", city: "Casablanca")
      workspace.orders.create!(customer: customer, customer_name: name, customer_phone: customer.phone,
        customer_city: customer.city, customer_address: "Synthetic address", total_cents: 12345,
        subtotal_cents: 12345, currency: "MAD", status: "in_transit", sendit_code: tracking)
    end
    sign_in
    get "/admin/delivery", params: { locale: "en" }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("OWN-TRACKING", "Own synthetic buyer", "123.45")
    expect(response.body).not_to include("FOREIGN-TRACKING", "Foreign synthetic buyer")
  end

  %w[fr en ar].each do |locale|
    it "renders localized labels in #{locale}" do
      sign_in
      get "/admin/delivery", params: { locale: locale }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("delivery_dashboard.title", locale: locale))
      expect(response.body).not_to match(/translation missing|translation_missing/i)
      expect(response.body).to include('dir="rtl"') if locale == "ar"
    end
  end

  it "redirects platform-only sessions without a tenant" do
    platform = User.create!(email: "platform-delivery-#{SecureRandom.hex(5)}@example.test", password: password, admin: true, super_admin: true)
    host! Store.base_domain
    post "/admin/login", params: { email: platform.email, password: password }
    expect(Admin::DeliverySummary).not_to receive(:new)
    get "/admin/delivery"
    expect(response).to redirect_to(admin_platform_path)
  end

  it "rejects a staff session on another tenant host" do
    sign_in
    foreign = Store.create!(slug: "foreign-#{SecureRandom.hex(5)}", name: "Synthetic foreign workspace")
    host! "#{foreign.slug}.#{Store.base_domain}"
    get "/admin/delivery"
    expect(response).to redirect_to(admin_login_path)
  end
end
