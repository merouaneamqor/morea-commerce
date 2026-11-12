# frozen_string_literal: true

require "rails_helper"

RSpec.describe Platform::IntegrationDiagnostics do
  let(:actor) { User.create!(email: "diag-#{SecureRandom.hex(5)}@example.test", password: "Synthetic-password-123!", super_admin: true, admin: true) }
  let(:store) { Store.create!(slug: "integ-#{SecureRandom.hex(5)}", name: "Synthetic integrations workspace", currency: "MAD", storefront_enabled: false) }
  let!(:shopify) do
    store.store_connections.create!(provider: "shopify", name: "Synthetic Seallo", external_domain: "diag-#{SecureRandom.hex(5)}.myshopify.com",
      shopify_app: "seallo_connect", shopify_oauth: true, shopify_api_error_code: "missing_scopes",
      shopify_sync_error: "private-provider-payload")
  end
  let!(:woo) do
    store.store_connections.create!(provider: "woocommerce", name: "Synthetic Woo", external_domain: "woo-#{SecureRandom.hex(5)}.example.test",
      webhook_secret: "synthetic-woo-signing-secret-12")
  end
  let!(:meta) { MetaAds::Connection.create!(store: store, status: "needs_reauthorization", last_error_code: "invalid_token") }
  let!(:sendit) do
    store.delivery_accounts.create!(provider: "sendit", name: "Sendit", account_type: "normal", is_active: true,
      credentials: { "api_key" => "pub-synthetic", "api_secret" => "sec-synthetic" }, connected_at: nil)
  end
  subject(:diagnostics) { described_class.new(actor: actor) }

  it "requires an active persisted superadmin" do
    merchant = store.users.create!(email: "merchant-#{SecureRandom.hex(5)}@example.test", password: "Synthetic-password-123!", admin: true)
    [ nil, merchant, User.new(super_admin: true), actor.tap { |user| user.update!(status: "suspended") } ].each do |user|
      expect { described_class.new(actor: user).failing_entries }.to raise_error(ActiveRecord::RecordNotFound)
      expect { described_class.new(actor: user).workspaces }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  it "summarizes failing connections with safe codes and without secrets" do
    failing = diagnostics.failing_entries
    expect(failing.map(&:provider)).to include("shopify", "meta_ads", "sendit")
    shopify_entry = failing.find { |entry| entry.id == shopify.id }
    expect(shopify_entry.error_code).to eq("missing_scopes")
    expect(shopify_entry).to be_failing
    dump = failing.map { |entry| entry.to_h.merge(entry.as_json) }.to_s
    expect(dump).not_to include("private-provider-payload", "pub-synthetic", "sec-synthetic", "synthetic-woo-signing-secret")
    expect(dump).not_to include("ciphertext", "access_token", "webhook_secret")
  end

  it "lists workspaces that have any connection and keeps GET summaries provider-free" do
    workspaces = diagnostics.workspaces
    expect(workspaces.map { |row| row.store.id }).to include(store.id)
    workspace = diagnostics.workspace(store)
    expect(workspace.entries.map(&:provider)).to include("shopify", "woocommerce", "meta_ads", "sendit")
    woo_entry = workspace.entries.find { |entry| entry.id == woo.id }
    expect(woo_entry.connection_state).to eq("configured")
    expect(workspace.entries.map(&:to_h).to_s).not_to include("synthetic-woo-signing-secret", "pub-synthetic")
  end

  it "does not treat healthy verified connections as failing" do
    shopify.update!(shopify_api_error_code: nil, shopify_sync_error: nil, shopify_api_verified_at: Time.current)
    meta.update!(status: "disconnected", last_error_code: nil)
    sendit.update!(connected_at: Time.current)
    expect(diagnostics.failing_entries.map(&:id)).not_to include(shopify.id, meta.id, sendit.id)
  end
end
