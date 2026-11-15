# frozen_string_literal: true

require "rails_helper"
require "nokogiri"

RSpec.describe "Checkout popup store setting", type: :request do
  let(:suffix) { SecureRandom.hex(5) }
  let(:password) { "Synthetic-co-#{suffix}-password" }
  let(:store) do
    Store.create!(
      name: "Boutique #{suffix}",
      slug: "co-#{suffix}",
      currency: "MAD",
      storefront_enabled: true,
      subscription_required: false
    )
  end
  let(:owner) { store.users.create!(email: "owner-#{suffix}@example.test", password: password, admin: true) }

  def sign_in
    host! "#{store.slug}.#{Store.base_domain}"
    post "/admin/login", params: { email: owner.email, password: password }
    expect(response).to have_http_status(:redirect)
  end

  def document
    Nokogiri::HTML(response.body)
  end

  it "defaults on" do
    expect(store.checkout_popup_enabled).to be(true)
  end

  it "shows the toggle on settings and persists enable / disable" do
    sign_in
    get edit_admin_store_path
    expect(response).to have_http_status(:ok)
    expect(document.at_css("#checkout-popup input[name='store[checkout_popup_enabled]']")).to be_present
    expect(response.body).not_to include("translation_missing")

    patch admin_store_path, params: { store: { checkout_popup_enabled: "0" } }
    expect(response).to redirect_to(edit_admin_store_path)
    expect(store.reload.checkout_popup_enabled).to be(false)

    patch admin_store_path, params: { store: { checkout_popup_enabled: "1" } }
    expect(response).to redirect_to(edit_admin_store_path)
    expect(store.reload.checkout_popup_enabled).to be(true)
  end

  it "cannot change another workspace by forged id" do
    other = Store.create!(name: "Other #{suffix}", slug: "other-co-#{suffix}", currency: "MAD", storefront_enabled: true)
    sign_in
    patch admin_store_path, params: { store: { id: other.id, store_id: other.id, checkout_popup_enabled: "0" } }
    expect(store.reload.checkout_popup_enabled).to be(false)
    expect(other.reload.checkout_popup_enabled).to be(true)
  end
end
