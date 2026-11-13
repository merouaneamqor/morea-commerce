# frozen_string_literal: true

require "rails_helper"
require "nokogiri"

RSpec.describe "Platform workspace reset", type: :request do
  let(:password) { "synthetic-reset-password-123" }
  let!(:owner) { User.create!(email: "reset-owner-#{SecureRandom.hex(4)}@example.test", password: password, admin: true, super_admin: true) }
  let!(:store) { Store.create!(slug: "reset-#{SecureRandom.hex(5)}", name: "Synthetic test workspace", currency: "MAD", storefront_enabled: false) }
  let!(:merchant) { store.users.create!(email: "merchant-#{SecureRandom.hex(4)}@example.test", password: password, admin: true) }
  let!(:customer) { store.customers.create!(name: "Synthetic buyer", phone: "0612345678", city: "Casablanca") }

  before do
    host! Store.base_domain
    store.orders.create!(customer: customer, customer_name: customer.name, customer_phone: customer.phone, customer_city: customer.city,
      customer_address: "Synthetic address", total_cents: 101, subtotal_cents: 101, currency: "MAD", status: "new")
  end

  def sign_in(user)
    post "/admin/login", params: { email: user.email, password: password, workspace: user.store&.slug }
    expect(response).to have_http_status(:redirect)
  end

  it "shows a confirmation form on the workspace page for a platform admin" do
    sign_in(owner)
    get edit_admin_tenant_path(store)

    form = Nokogiri::HTML(response.body).at_css("form[action='#{reset_admin_tenant_path(store)}']")
    expect(form).to be_present
    expect(form.at_css("input[name='confirmation']")).to be_present
  end

  it "resets the workspace when the slug is confirmed" do
    sign_in(owner)

    expect { post reset_admin_tenant_path(store), params: { confirmation: store.slug } }.to change { store.orders.count }.from(1).to(0)

    expect(response).to redirect_to(admin_tenant_path(store))
    expect(flash[:notice]).to include(store.name)
    expect(store.customers.count).to eq(0)
    expect(store.reload.users).to contain_exactly(merchant)
    expect(AuditEvent.where(action: "store.reset", store_id: store.id, actor_user_id: owner.id).count).to eq(1)
  end

  it "keeps the data and explains why when the confirmation is wrong" do
    sign_in(owner)

    expect { post reset_admin_tenant_path(store), params: { confirmation: "nope" } }.not_to change { store.orders.count }

    expect(response).to redirect_to(edit_admin_tenant_path(store))
    expect(flash[:alert]).to eq(I18n.t("platform_admin.reset.denied.confirmation_mismatch"))
  end

  it "is not available to a workspace admin" do
    sign_in(merchant)

    expect { post reset_admin_tenant_path(store), params: { confirmation: store.slug } }.not_to change { store.orders.count }

    expect(response).to have_http_status(:redirect)
    expect(response).not_to redirect_to(admin_platform_path)
  end

  it "requires a signed-in session" do
    expect { post reset_admin_tenant_path(store), params: { confirmation: store.slug } }.not_to change { store.orders.count }

    expect(response).to redirect_to(admin_login_path)
  end
end
