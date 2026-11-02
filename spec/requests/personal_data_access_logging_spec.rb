# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Personal data access logging", type: :request do
  let(:password) { "synthetic-password-123" }
  let(:store) { Store.create!(slug: "audit-#{SecureRandom.hex(5)}", name: "Synthetic audit workspace", currency: "MAD") }
  let(:staff) { store.users.create!(name: "Ana", email: "ana-#{SecureRandom.hex(5)}@example.test", password: password, admin: true) }
  let(:customer) { store.customers.create!(name: "Synthetic Buyer", phone: "0612345678", city: "Casablanca") }
  let!(:order) do
    store.orders.create!(customer: customer, status: "new", customer_name: "Synthetic Buyer", customer_phone: "0612345678",
      customer_city: "Casablanca", customer_address: "Synthetic Street 1", total_cents: 12345, currency: "MAD")
  end

  def sign_in(user = staff, workspace: store)
    host! "#{workspace.slug}.#{Store.base_domain}"
    post "/admin/login", params: { email: user.email, password: password }
    expect(response).to have_http_status(:redirect)
  end

  def reads
    AuditEvent.personal_data_reads.order(:id)
  end

  describe "admin screens" do
    it "records who opened an order, without storing the buyer's details" do
      sign_in
      get admin_order_path(order)

      expect(response).to have_http_status(:ok)
      event = reads.last
      expect(event).to have_attributes(store_id: store.id, actor_user_id: staff.id, source: "ui", subject_type: "Order",
        subject_id: order.id, acting_as_platform: false)
      expect(event.metadata).to eq("surface" => "admin/orders#show")
      stored = event.attributes.values.join(" ")
      expect([ "Synthetic Buyer", "0612345678", "Synthetic Street 1" ]).to all(satisfy { |value| !stored.include?(value) })
    end

    it "records list and customer views" do
      sign_in
      get admin_orders_path
      get admin_customer_path(customer)

      expect(reads.map { |event| event.metadata["surface"] }).to eq([ "admin/orders#index", "admin/customers#show" ])
      expect(reads.last.subject).to eq(customer)
    end

    it "does not log screens without buyer details or unsuccessful requests" do
      sign_in
      get admin_products_path
      get admin_order_path(id: 0)

      expect(reads.count).to eq(0)
    end

    it "logs nothing for a signed-out visitor" do
      host! "#{store.slug}.#{Store.base_domain}"
      get admin_order_path(order)

      expect(response).to redirect_to("/admin/login")
      expect(reads.count).to eq(0)
    end

    it "attributes events to the workspace that was actually read" do
      other = Store.create!(slug: "audit-other-#{SecureRandom.hex(4)}", name: "Other workspace", currency: "MAD")
      other_staff = other.users.create!(name: "Omar", email: "omar-#{SecureRandom.hex(5)}@example.test", password: password, admin: true)
      sign_in(other_staff, workspace: other)
      get admin_orders_path

      expect(reads.pluck(:store_id)).to eq([ other.id ])
    end
  end

  describe "API and MCP" do
    def run(query, source: "api")
      MoreaSchema.execute(query, context: { store: store, source: source, actor_label: "api-token", ip: "203.0.113.9" })
    end

    it "records customer lookups per surface" do
      run("{ customers { name } }")
      run("{ customers { name } }", source: "mcp")

      expect(reads.pluck(:source, :store_id)).to eq([ [ "api", store.id ], [ "mcp", store.id ] ])
      expect(reads.first.metadata).to eq("surface" => "graphql.customers")
      expect(reads.first.ip).to eq("203.0.113.9")
    end

    it "records a single customer, contact-bearing order desk reads and customer exports only" do
      run(%({ customer(phone: "0612345678") { name } }))
      expect(reads.last).to have_attributes(subject_type: "Customer", subject_id: customer.id)

      expect { run(%({ orderDesk(number: "#{order.number}") })) }.not_to change(AuditEvent, :count)
      expect { run(%({ orderDesk(number: "#{order.number}", includeContact: true) })) }.to change(AuditEvent, :count).by(1)
    end
  end

  describe PersonalDataAudit do
    it "never blocks the read when the log cannot be written" do
      allow(AuditEvent).to receive(:create!).and_raise(ActiveRecord::StatementInvalid, "synthetic outage")
      expect(Rails.error).to receive(:report).with(instance_of(ActiveRecord::StatementInvalid), hash_including(handled: true))

      expect(described_class.record(store: store, source: "ui", surface: "admin/orders#index")).to be_nil
    end

    it "keeps only whitelisted, short metadata" do
      described_class.record(store: store, source: "api", surface: "graphql.customers", phone: "0612345678", count: 3, kind: "x" * 500)

      expect(reads.last.metadata.keys).to contain_exactly("surface", "count", "kind")
      expect(reads.last.metadata["kind"].length).to eq(120)
    end
  end

  describe AuditEvent do
    it "is append-only" do
      event = described_class.create!(store: store, source: "ui", action: PersonalDataAudit::ACTION)

      expect { event.update!(action: "tampered") }.to raise_error(ActiveRecord::ReadOnlyRecord)
      expect { event.destroy }.to raise_error(ActiveRecord::ReadOnlyRecord)
      expect(event.reload.action).to eq(PersonalDataAudit::ACTION)
    end
  end
end
