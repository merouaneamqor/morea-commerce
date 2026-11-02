# frozen_string_literal: true

require "rails_helper"

RSpec.describe PlatformTools do
  let(:store) { Store.create!(name: "Synthetic workspace", slug: "mcp-#{SecureRandom.hex(5)}", currency: "MAD") }
  let(:actor) do
    User.create!(name: "Platform operator", email: "operator-#{SecureRandom.hex(5)}@example.test",
      password: "Synthetic-safe-password-123", super_admin: true)
  end
  let(:context) { { user: actor } }

  def payload(response)
    part = response.content.first
    JSON.parse(part[:text] || part["text"])
  end

  it "supports a platform-only actor and rechecks authorization on every call" do
    expect(PlatformTools::ListTenants.call(server_context: context).error?).to be(false)
    actor.update!(status: "suspended")
    expect(PlatformTools::ListTenants.call(server_context: context).error?).to be(true)
  end

  it "rejects a demoted actor even when the context contains the old object" do
    actor.update!(store: store)
    User.where(id: actor.id).update_all(super_admin: false)
    expect(PlatformTools::ListTenants.call(server_context: context).error?).to be(true)
  end

  it "rejects a merchant at server construction" do
    user = store.users.create!(name: "Merchant", email: "merchant@example.test",
      password: "Synthetic-safe-password-123", admin: true)
    expect { PlatformServer.build(user: user) }.to raise_error(PlatformTools::Unauthorized)
  end

  it "paginates tenant results and rejects unbounded input" do
    store
    other = Store.create!(name: "Second workspace", slug: "mcp-other-#{SecureRandom.hex(5)}", currency: "MAD")
    result = payload(PlatformTools::ListTenants.call(server_context: context, after_id: store.id - 1, limit: 1))
    expect(result.fetch("records").map { |row| row.fetch("id") }).to eq([ store.id ])
    expect(result.fetch("next_after_id")).to eq(store.id)
    next_page = payload(PlatformTools::ListTenants.call(server_context: context, after_id: store.id, limit: 1))
    expect(next_page.fetch("records").first.fetch("id")).to eq(other.id)
    expect(PlatformTools::ListTenants.call(server_context: context, limit: 101).error?).to be(true)
  end

  it "requires confirmation and preserves lifecycle safeguards" do
    staff = store.users.create!(name: "Staff", email: "staff@example.test", password: "Synthetic-safe-password-123", admin: true)
    tool = PlatformTools::TransitionPlatformUser
    expect(tool.call(server_context: context, user_id: staff.id, action: "suspend").error?).to be(true)
    expect(staff.reload.status).to eq("active")
    expect(tool.call(server_context: context, user_id: actor.id, action: "archive", confirm: true).error?).to be(true)
    expect(actor.reload.status).to eq("active")
    expect(tool.call(server_context: context, user_id: staff.id, action: "suspend", confirm: true).error?).to be(false)
    expect(staff.reload.status).to eq("suspended")
  end

  it "scopes invoices to the selected tenant and enforces transition state" do
    invoice = Invoice.build_for_store(store).tap(&:save!)
    other = Store.create!(name: "Other workspace", slug: "other-#{SecureRandom.hex(5)}", currency: "MAD")
    tool = PlatformTools::TransitionTenantInvoice
    expect(tool.call(server_context: context, tenant_id: other.id, invoice_id: invoice.id, action: "issue", confirm: true).error?).to be(true)
    expect(tool.call(server_context: context, tenant_id: store.id, invoice_id: invoice.id, action: "issue").error?).to be(true)
    expect(tool.call(server_context: context, tenant_id: store.id, invoice_id: invoice.id, action: "mark_paid", confirm: true).error?).to be(true)
    expect(invoice.reload.status).to eq("draft")
    expect(tool.call(server_context: context, tenant_id: store.id, invoice_id: invoice.id, action: "issue", confirm: true).error?).to be(false)
    expect(tool.call(server_context: context, tenant_id: store.id, invoice_id: invoice.id, action: "mark_paid", confirm: true).error?).to be(false)
    expect(invoice.reload.status).to eq("paid")
    expect(store.reload.billing_status).to eq("active")
  end
end
