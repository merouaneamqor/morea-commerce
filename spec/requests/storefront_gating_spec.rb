# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Storefront enablement gating", type: :request do
  let(:password) { "synthetic-password-123" }
  let(:store) do
    Store.create!(
      slug: "gate-#{SecureRandom.hex(4)}",
      name: "Gated Store",
      currency: "MAD",
      storefront_enabled: false
    )
  end
  let!(:owner) do
    store.users.create!(name: "Owner", email: "owner-#{SecureRandom.hex(4)}@example.test", password: password, admin: true)
  end
  let!(:product) do
    store.products.create!(name: "Hidden", slug: "hidden", status: "active", price_cents: 2_000)
  end

  it "404s localized shopping and checkout while admin sign-in still works" do
    host! "#{store.slug}.#{Store.base_domain}"

    %w[/en /fr /ar /en/cart /en/checkout /en/products/hidden /en/orders/track /fr/cart /ar/checkout].each do |path|
      get path
      expect(response).to have_http_status(:not_found), "expected 404 for #{path}"
    end

    get "/admin/login"
    expect(response).to have_http_status(:ok)

    post "/admin/login", params: { email: owner.email, password: password }
    expect(response).to have_http_status(:redirect)
  end

  it "404s apex localized shopping routes" do
    host! Store.base_domain

    get "/en/cart"
    expect(response).to have_http_status(:not_found)
  end

  it "serves shopping routes after the storefront is enabled" do
    store.update!(storefront_enabled: true)
    host! "#{store.slug}.#{Store.base_domain}"

    get "/en"
    expect(response).to have_http_status(:ok)

    get "/en/cart"
    expect(response).to have_http_status(:ok)

    get "/en/products/hidden"
    expect(response).to have_http_status(:ok)
  end
end
