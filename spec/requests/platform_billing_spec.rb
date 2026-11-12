# frozen_string_literal: true

require "rails_helper"
require "nokogiri"

RSpec.describe "Platform subscription billing", type: :request do
  let(:password) { "synthetic-platform-password-123" }
  let!(:store) do
    Store.create!(
      slug: "bill-#{SecureRandom.hex(5)}",
      name: "Synthetic billing workspace",
      currency: "MAD",
      billing_status: "past_due",
      billing_amount_cents: 9900,
      billing_period_ends_on: Date.current + 5.days
    )
  end
  let!(:owner) do
    User.create!(email: "billing-#{SecureRandom.hex(5)}@example.test", password: password, super_admin: true, admin: true)
  end

  before { host! Store.base_domain }

  def sign_in(user)
    post "/admin/login", params: { email: user.email, password: password }
  end

  def invoice_attrs(**extra)
    {
      period_starts_on: Date.current.beginning_of_month,
      period_ends_on: Date.current.end_of_month,
      billing_interval: "monthly",
      amount_cents: 9900
    }.merge(extra)
  end

  it "requires authentication and rejects merchant administrators" do
    get "/admin/platform/billing"
    expect(response).to redirect_to(admin_login_path)

    merchant = store.users.create!(email: "merchant-bill-#{SecureRandom.hex(4)}@example.test", password: password, admin: true)
    sign_in(merchant)
    get "/admin/platform/billing"
    expect(response).to redirect_to(admin_root_path)
  end

  it "lists overdue subscription invoices without merchant order revenue" do
    travel_to Time.find_zone!("Africa/Casablanca").local(2026, 11, 12, 12) do
      overdue = store.invoices.create!(**invoice_attrs(status: "issued", due_on: Date.current - 3, issued_at: 1.week.ago))
      customer = store.customers.create!(name: "Synthetic buyer", phone: "0612345678", city: "Casablanca")
      store.orders.create!(
        customer: customer, customer_name: customer.name, customer_phone: customer.phone,
        customer_city: customer.city, customer_address: "Synthetic address", currency: "MAD",
        subtotal_cents: 999_99, total_cents: 999_99, status: "delivered"
      )
      sign_in(owner)

      get "/admin/platform/billing"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(overdue.number, store.name)
      document = Nokogiri::HTML(response.body)
      expect(document.at_css("#platform-billing-outstanding").text).to include("99")
      expect(document.at_css("#platform-billing-outstanding").text).not_to include("999")
      expect(response.body).to include(admin_tenant_invoice_path(store, overdue))
      expect(response.body).not_to match(/translation missing|translation_missing/i)
    end
  end

  it "records payment_reference on mark_paid, activates billing, and audits" do
    invoice = store.invoices.create!(**invoice_attrs(status: "issued", due_on: Date.current - 1, issued_at: 2.days.ago))
    sign_in(owner)

    expect do
      post mark_paid_admin_tenant_invoice_path(store, invoice), params: { payment_reference: "TRX-SEALLO-42" }
    end.to change(AuditEvent, :count).by(1)

    expect(response).to redirect_to(admin_tenant_invoice_path(store, invoice))
    follow_redirect!
    expect(response.body).to include("Subscription status: active")
    expect(response.body).to include("TRX-SEALLO-42")

    invoice.reload
    store.reload
    expect(invoice).to have_attributes(status: "paid", payment_reference: "TRX-SEALLO-42")
    expect(store.billing_status).to eq("active")

    event = AuditEvent.order(:id).last
    expect(event).to have_attributes(action: "invoice.mark_paid", acting_as_platform: true)
    expect(event.metadata["payment_reference"]).to eq("TRX-SEALLO-42")
    expect(event.metadata["invoice_number"]).to eq(invoice.number)
  end

  it "rejects payment_reference longer than 120 characters" do
    invoice = store.invoices.create!(**invoice_attrs(status: "issued", due_on: Date.current + 3, issued_at: Time.current))
    sign_in(owner)

    post mark_paid_admin_tenant_invoice_path(store, invoice), params: { payment_reference: "x" * 121 }
    expect(response).to redirect_to(admin_tenant_invoice_path(store, invoice))
    expect(invoice.reload.status).to eq("issued")
    expect(invoice.payment_reference).to be_nil
  end
end
