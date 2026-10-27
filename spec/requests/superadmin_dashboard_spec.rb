require "rails_helper"
require "nokogiri"

RSpec.describe "Superadmin dashboard", type: :request do
  let(:password) { "synthetic-superadmin-password-123" }
  let!(:store) { Store.create!(slug: "sa-#{SecureRandom.hex(5)}", name: "First synthetic dashboard workspace", currency: "MAD") }
  let!(:other_store) do
    Store.create!(slug: "sa-other-#{SecureRandom.hex(5)}", name: "Other synthetic dashboard workspace",
      currency: "EUR", storefront_enabled: false)
  end
  let!(:owner) do
    User.create!(email: "superadmin-#{SecureRandom.hex(5)}@example.test", password: password,
      super_admin: true, admin: true)
  end

  before { host! Store.base_domain }

  def sign_in(user)
    post "/admin/login", params: { email: user.email, password: password }
    expect(response).to have_http_status(:redirect)
  end

  def dashboard
    get "/superadmin", params: { locale: "en" }
  end

  it "requires authentication before displaying platform data" do
    dashboard

    expect(response).to redirect_to(admin_login_path)
    expect(response.body).not_to include(other_store.name)
  end

  it "rejects merchant administrators on their tenant host" do
    host! "#{store.slug}.#{Store.base_domain}"
    merchant = store.users.create!(email: "merchant-#{SecureRandom.hex(5)}@example.test", password: password, admin: true)
    sign_in(merchant)

    dashboard

    expect(response).to redirect_to(admin_root_path)
    expect(response.body).not_to include(other_store.name)
  end

  it "invalidates an existing superadmin session after suspension" do
    sign_in(owner)
    owner.update!(status: "suspended")

    dashboard

    expect(response).to redirect_to(admin_login_path)
    expect(response.body).not_to include(other_store.name)
  end

  it "rejects an unknown tenant host even with a superadmin session" do
    sign_in(owner)
    host! "unknown-#{SecureRandom.hex(5)}.#{Store.base_domain}"

    dashboard

    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include(other_store.name)
  end

  %i[apex tenant unpublished_tenant].each do |host_type|
    it "shows cross-workspace operations to a platform-only superadmin on the #{host_type} host" do
      host! "#{store.slug}.#{Store.base_domain}" if host_type == :tenant
      host! "#{other_store.slug}.#{Store.base_domain}" if host_type == :unpublished_tenant
      sign_in(owner)

      dashboard

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(store.name, other_store.name)
      expect(response.body).not_to match(/translation missing|translation_missing/i)
    end
  end

  it "shows subscription invoice amounts separately from merchant order values" do
    travel_to Time.find_zone!("Africa/Casablanca").local(2026, 10, 15, 12) do
      invoice_attributes = { period_starts_on: Date.current.beginning_of_month,
        period_ends_on: Date.current.end_of_month, billing_interval: "monthly" }
      store.invoices.create!(**invoice_attributes, status: "paid", paid_at: Time.current, amount_cents: 12345)
      store.invoices.create!(**invoice_attributes, status: "issued", due_on: Date.current - 1, amount_cents: 4567)
      other_store.invoices.create!(**invoice_attributes, status: "issued", due_on: Date.current + 7, amount_cents: 101)
      other_store.invoices.create!(**invoice_attributes, status: "draft", amount_cents: 88888)
      customer = store.customers.create!(name: "Synthetic buyer", phone: "0612345678", city: "Casablanca")
      store.orders.create!(customer: customer, customer_name: customer.name, customer_phone: customer.phone,
        customer_city: customer.city, customer_address: "Synthetic address", currency: "MAD",
        subtotal_cents: 99999, total_cents: 99999, status: "delivered")
      sign_in(owner)

      dashboard

      expect(response).to have_http_status(:ok)
      document = Nokogiri::HTML(response.body)
      expect(document.at_css("#platform-paid strong").text).to eq("MAD 123.45")
      expect(document.at_css("#platform-outstanding strong").text).to eq("MAD 46.68")
      expect(document.at_css("#platform-overdue strong").text).to eq("MAD 45.67")
      expect(document.at_css("#platform-overdue").text).to include("Overdue invoices (1)")
    end
  end

  it "bounds the newest-workspace list and links to authorized workspace actions" do
    store.update!(created_at: 2.years.ago)
    other_store.update!(created_at: 1.year.ago)
    newest = 10.times.map do |index|
      Store.create!(slug: "sa-recent-#{SecureRandom.hex(5)}", name: "Recent synthetic workspace #{index}",
        created_at: index.minutes.ago)
    end
    sign_in(owner)

    dashboard

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    panel = document.css(".panel").find { |node| node.at_css("h3")&.text == "Newest workspaces" }
    expect(panel).to be_present
    expect(panel.css("tbody tr").length).to eq(10)
    newest.each { |workspace| expect(panel.text).to include(workspace.name) }
    expect(panel.text).not_to include(store.name, other_store.name)
    expect(panel.at_css("a[href='#{edit_admin_tenant_path(newest.first)}']")).to be_present
    form = panel.at_css("form[action='#{enter_admin_tenant_path(newest.first)}']")
    expect(form["method"]).to eq("post")
  end
end
