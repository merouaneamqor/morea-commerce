# frozen_string_literal: true

require "rails_helper"
require "nokogiri"

RSpec.describe "Platform audit events", type: :request do
  let(:password) { "synthetic-platform-password-123" }
  let!(:store) { Store.create!(slug: "aud-#{SecureRandom.hex(5)}", name: "Synthetic audit workspace", currency: "MAD") }
  let!(:owner) do
    User.create!(email: "audit-#{SecureRandom.hex(5)}@example.test", password: password, super_admin: true, admin: true)
  end

  before { host! Store.base_domain }

  def sign_in(user)
    post "/admin/login", params: { email: user.email, password: password }
  end

  def create_event(**attrs)
    AuditEvent.create!(
      {
        store: store,
        actor_user: owner,
        actor_label: owner.email,
        source: "ui",
        acting_as_platform: true,
        action: "invoice.mark_paid",
        metadata: { invoice_number: "INV-TEST", payment_reference: "REF-1", outcome: "ok" }
      }.merge(attrs)
    )
  end

  it "requires authentication and rejects merchant administrators" do
    get "/admin/platform/audit"
    expect(response).to redirect_to(admin_login_path)

    merchant = store.users.create!(email: "merchant-aud-#{SecureRandom.hex(4)}@example.test", password: password, admin: true)
    sign_in(merchant)
    get "/admin/platform/audit"
    expect(response).to redirect_to(admin_root_path)
  end

  it "lists and filters platform audit events" do
    matching = create_event(action: "invoice.mark_paid")
    create_event(action: "platform_user.lifecycle", metadata: { lifecycle: "suspend", outcome: "ok" })
    sign_in(owner)

    get "/admin/platform/audit", params: { action_name: "invoice.mark", store_id: store.id, actor: owner.email.split("@").first }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(matching.action)
    expect(response.body).to include(admin_platform_audit_event_path(matching))
    expect(response.body).not_to include("platform_user.lifecycle")
    expect(response.body).not_to match(/translation missing|translation_missing/i)
  end

  it "shows safe metadata only and omits secret-like keys" do
    event = create_event(
      metadata: {
        invoice_number: "INV-SAFE",
        payment_reference: "REF-SAFE",
        outcome: "ok",
        api_token: "should-never-appear",
        password: "also-secret"
      }
    )
    sign_in(owner)

    get "/admin/platform/audit/#{event.id}"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("INV-SAFE", "REF-SAFE")
    expect(response.body).not_to include("should-never-appear")
    expect(response.body).not_to include("also-secret")
    expect(response.body).to include(I18n.t("platform_admin.audit.metadata_note"))
  end
end
