# frozen_string_literal: true

require "rails_helper"
require "nokogiri"

RSpec.describe "Store connection deletion", type: :request do
  let(:password) { "synthetic-deletion-password-123" }
  let(:store) { Store.create!(slug: "delete-#{SecureRandom.hex(5)}", name: "Synthetic workspace", currency: "MAD", storefront_enabled: false) }
  let(:staff) { store.users.create!(email: "delete-#{SecureRandom.hex(5)}@example.test", password: password, admin: true) }
  let(:connection) { store.store_connections.create!(name: "Synthetic Shopify", provider: "shopify", external_domain: "synthetic.myshopify.com", shopify_oauth: true) }

  def sign_in(user = staff)
    host! Store.base_domain
    post admin_login_path, params: { email: user.email, password: password }
    expect(response).to have_http_status(:redirect)
  end

  it "deletes an unused connection and its locally stored authorization" do
    sign_in
    connection.update!(shopify_access_token: "synthetic-private-token", shopify_refresh_token: "synthetic-refresh-token",
      shopify_access_token_expires_at: 1.hour.from_now, shopify_refresh_token_expires_at: 30.days.from_now,
      shopify_oauth_state_digest: Digest::SHA256.hexdigest("synthetic-state"), shopify_oauth_state_expires_at: 10.minutes.from_now)
    expect(Connections::ShopifyApi).not_to receive(:new)
    expect { delete admin_store_connection_path(connection) }.to change(StoreConnection, :count).by(-1)
    expect(response).to have_http_status(:see_other)
    expect(response).to redirect_to(admin_store_connections_path)
    expect(StoreConnection.exists?(connection.id)).to eq(false)
  end

  it "also deletes unused webhook connections" do
    sign_in
    webhook = store.store_connections.create!(name: "Synthetic Woo", provider: "woocommerce", external_domain: "synthetic.example.test", webhook_secret: "synthetic-signing-secret")
    expect { delete admin_store_connection_path(webhook) }.to change(StoreConnection, :count).by(-1)
    expect(response).to redirect_to(admin_store_connections_path)
  end

  it "preserves accepted receipts, imported orders and their commercial edit lock" do
    sign_in
    customer = store.customers.create!(name: "Synthetic buyer", phone: "0612345678", city: "Casablanca")
    order = store.orders.create!(customer: customer, customer_name: customer.name, customer_phone: customer.phone,
      customer_city: customer.city, customer_address: "Synthetic address", subtotal_cents: 100, total_cents: 100, currency: "MAD", status: "new")
    receipt = connection.external_order_receipts.create!(external_id: "synthetic-accepted", status: "accepted", received_at: Time.current, order: order)
    expect { delete admin_store_connection_path(connection) }.not_to change(StoreConnection, :count)
    expect(response).to redirect_to(admin_store_connection_path(connection))
    expect(receipt.reload.order_id).to eq(order.id)
    expect(order.reload).not_to be_editable
    follow_redirect!
    expect(response.body).to include(I18n.t("connections.delete_blocked"))
  end

  it "preserves rejected delivery history too" do
    sign_in
    receipt = connection.external_order_receipts.create!(external_id: "synthetic-rejected", status: "rejected", received_at: Time.current, error_code: "unsupported_currency")
    expect { delete admin_store_connection_path(connection) }.not_to change(StoreConnection, :count)
    expect(response).to redirect_to(admin_store_connection_path(connection))
    expect(ExternalOrderReceipt.exists?(receipt.id)).to eq(true)
  end

  it "hides another workspace's connection" do
    sign_in
    other = Store.create!(slug: "other-delete-#{SecureRandom.hex(5)}", name: "Other synthetic workspace", currency: "MAD")
    foreign = other.store_connections.create!(name: "Foreign Shopify", provider: "shopify", external_domain: "foreign.myshopify.com", shopify_oauth: true)
    expect { delete admin_store_connection_path(foreign) }.not_to change(StoreConnection, :count)
    expect(response).to have_http_status(:not_found)
  end

  it "requires authentication and a selected workspace" do
    host! Store.base_domain
    connection
    expect { delete admin_store_connection_path(connection) }.not_to change(StoreConnection, :count)
    expect(response).to redirect_to(admin_login_path)
    owner = User.create!(email: "owner-delete-#{SecureRandom.hex(5)}@example.test", password: password, admin: true, super_admin: true)
    sign_in(owner)
    expect { delete admin_store_connection_path(connection) }.not_to change(StoreConnection, :count)
    expect(response).to have_http_status(:not_found)
  end

  it "renders a localized delete form with confirmation in every language" do
    sign_in
    %w[fr en ar].each do |locale|
      get admin_store_connection_path(connection), params: { locale: locale }
      expect(response).to have_http_status(:ok)
      document = Nokogiri::HTML(response.body)
      form = document.at_css("form[action='#{admin_store_connection_path(connection)}'] input[name='_method'][value='delete']").ancestors("form").first
      expect(form["action"]).to eq(admin_store_connection_path(connection))
      expect(form["data-turbo-confirm"]).to eq(I18n.t("connections.delete_confirm", locale: locale, name: connection.name))
      expect(form.text).to include(I18n.t("connections.delete", locale: locale))
      expect(response.body).not_to match(/translation missing|translation_missing/i)
    end
  end
end
