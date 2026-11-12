# frozen_string_literal: true

require "rails_helper"

RSpec.describe Platform::IntegrationDiagnostics do
  let(:actor) do
    User.create!(
      email: "diag-#{SecureRandom.hex(5)}@example.test",
      password: "synthetic-diagnostics-password-123",
      admin: true,
      super_admin: true
    )
  end
  let(:store) { Store.create!(slug: "diag-#{SecureRandom.hex(5)}", name: "Diag store", currency: "MAD") }

  it "returns failing Shopify connections for a super admin without tokens" do
    connection = store.store_connections.create!(
      provider: "shopify",
      name: "Diag shop",
      external_domain: "diag-#{SecureRandom.hex(5)}.myshopify.com",
      shopify_app: "seallo_connect",
      shopify_oauth: true,
      shopify_api_error_code: "missing_scopes"
    )

    entries = described_class.new(actor: actor).failing_entries
    entry = entries.find { |row| row.id == connection.id }

    expect(entry).to be_present
    expect(entry.provider).to eq("shopify")
    expect(entry.error_code).to eq("missing_scopes")
    expect(entry.failing?).to eq(true)
    expect(entry.as_json.to_s).not_to match(/token|secret|ciphertext/i)
  end

  it "rejects non-super-admin actors" do
    merchant = store.users.create!(
      email: "diag-merchant-#{SecureRandom.hex(5)}@example.test",
      password: "synthetic-diagnostics-password-123",
      admin: true
    )
    expect {
      described_class.new(actor: merchant).workspaces
    }.to raise_error(ActiveRecord::RecordNotFound)
  end
end
