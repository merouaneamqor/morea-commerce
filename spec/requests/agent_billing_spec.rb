require "rails_helper"
require "nokogiri"

# The owner's Facturation page: what each agent is owed, and the payout for the delivered orders the owner ticks, with how it was made (cash or bank
# transfer), a reference and an optional proof.
RSpec.describe "Agent billing (owner)", type: :request do
  let(:password) { "synthetic-password-123" }
  let(:store) { Store.create!(slug: "bl-#{SecureRandom.hex(5)}", name: "Walkfit", currency: "MAD") }
  let!(:owner) { store.users.create!(name: "Owner", email: "owner-#{SecureRandom.hex(4)}@example.test", password: password, admin: true) }
  let!(:saida) { store.users.create!(name: "Saida", email: "saida-#{SecureRandom.hex(4)}@example.test", password: password, admin: false, confirmation_role: "agent", pay_per_delivery_cents: 800, return_penalty_cents: 300) }
  let!(:omar) { store.users.create!(name: "Omar", email: "omar-#{SecureRandom.hex(4)}@example.test", password: password, admin: false, confirmation_role: "agent", pay_per_delivery_cents: 800) }
  let(:customer) { store.customers.create!(name: "Client", phone: "0612345678") }
  let(:png) { Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==") }
  let!(:first_order) { delivered_for(saida, "P1", delivered: 3.days.ago) }
  let!(:second_order) { delivered_for(saida, "P2", delivered: 2.days.ago) }

  def sign_in(user)
    host! "#{store.slug}.#{Store.base_domain}"
    post "/admin/login", params: { email: user.email, password: password }
  end

  def page = Nokogiri::HTML(response.body)

  def upload(name, content, type)
    file = Tempfile.new([ "proof", File.extname(name) ])
    file.binmode
    file.write(content)
    file.rewind
    Rack::Test::UploadedFile.new(file.path, type, true, original_filename: name)
  end

  def delivered_for(agent, number, status: "delivered", delivered: 2.days.ago)
    order = store.orders.create!(customer: customer, number: number, status: status, currency: "MAD", customer_name: "Client", customer_phone: "0612345678",
      customer_city: "Fès", customer_address: "Rue 1", subtotal_cents: 20_000, total_cents: 20_000, confirmed_at: 4.days.ago, delivered_at: (delivered if status == "delivered"))
    OrderConfirmation.create!(store: store, order: order, disposition: "confirmed", assigned_user: agent, claimed_at: 4.days.ago)
    order
  end

  def pay(agent: saida, orders: [ first_order, second_order ], **params)
    post admin_agent_billing_pay_path, params: { user_id: agent.id, order_ids: orders.map(&:id), payment_method: "cash" }.merge(params)
  end

  it "shows each agent what they are owed and the orders to tick, and only to the owner" do
    sign_in(owner)
    get admin_agent_billing_path
    expect(response).to have_http_status(:ok)
    expect(page.at_css("[data-agent-row='#{saida.id}']")["data-unpaid"]).to eq("1600")
    expect(page.css("[data-agent-orders='#{saida.id}'] input[name='order_ids[]']").map { |box| box["value"].to_i }).to eq([ first_order.id, second_order.id ])
    expect(page.at_css("[data-agent-row='#{omar.id}'] [data-nothing-to-pay]")).to be_present
    expect(page.at_css("[data-pay-open]")).to be_present

    delete admin_logout_path rescue nil
    sign_in(saida)
    get admin_agent_billing_path
    expect(response).to redirect_to(admin_my_stats_path)
    pay
    expect(AgentPayment.count).to eq(0)
  end

  it "pays only the ticked orders, once each, and the rest stays to pay" do
    sign_in(owner)
    pay(orders: [ first_order ], reference: "Reçu 12")
    expect(response).to redirect_to(admin_agent_billing_path)
    payment = AgentPayment.last
    expect(payment).to have_attributes(user_id: saida.id, paid_by_id: owner.id, amount_cents: 800, payment_method: "cash", reference: "Reçu 12")
    expect(payment.items.pluck(:order_id)).to eq([ first_order.id ])

    get admin_agent_billing_path
    expect(page.at_css("[data-agent-row='#{saida.id}']")["data-unpaid"]).to eq("800")
    expect(page.css("[data-agent-orders='#{saida.id}'] input[name='order_ids[]']").map { |box| box["value"].to_i }).to eq([ second_order.id ])

    expect { pay(orders: [ first_order ]) }.not_to change(AgentPayment, :count)
    expect(flash[:alert]).to be_present
    pay(orders: [ second_order ])
    expect(AgentPayment.count).to eq(2)
    get admin_agent_billing_path
    expect(page.at_css("[data-agent-row='#{saida.id}'] [data-nothing-to-pay]")).to be_present
  end

  it "subtracts what a return cost from the payment" do
    returned = delivered_for(saida, "R1", status: "returned")
    AgentDeduction.create!(store: store, user: saida, order: returned, amount_cents: 300)
    sign_in(owner)
    pay
    payment = AgentPayment.last
    expect(payment).to have_attributes(amount_cents: 1600, deductions_cents: 300)
    expect(payment.cash_cents).to eq(1300)
  end

  it "takes a bank transfer with or without a proof, and shows the proof to the owner and to the agent" do
    sign_in(owner)
    pay(orders: [ first_order ], payment_method: "bank_transfer", reference: "VIR-77")
    expect(AgentPayment.last).to have_attributes(payment_method: "bank_transfer", reference: "VIR-77")
    expect(AgentPayment.last.proof).not_to be_attached

    pay(orders: [ second_order ], payment_method: "bank_transfer", reference: "VIR-78", proof: upload("virement.png", png, "image/png"))
    payment = AgentPayment.last
    expect(payment.proof).to be_attached

    get admin_agent_billing_path
    row = page.at_css("[data-payment='#{payment.id}']")
    expect(row["data-method"]).to eq("bank_transfer")
    expect(row.at_css("[data-proof-link]")["href"]).to include("/rails/active_storage/blobs")
    expect(row.text).to include("VIR-78")

    delete admin_logout_path rescue nil
    sign_in(saida)
    get admin_my_billing_path
    expect(page.at_css("[data-payment] a[href*='active_storage']")).to be_present
  end

  it "refuses an unknown method, a proof that is not an image or a PDF, no order, and orders that are not the agent's" do
    foreign = delivered_for(omar, "O1")
    sign_in(owner)
    pay(payment_method: "crypto")
    pay(orders: [])
    expect(flash[:alert]).to include("at least one")
    pay(orders: [ foreign ])
    expect(flash[:alert]).to include("cannot be paid")
    pay(payment_method: "bank_transfer", proof: upload("virement.txt", "hello", "text/plain"))
    expect(flash[:alert]).to include("PDF")
    expect(AgentPayment.count).to eq(0)

    pay(payment_method: "bank_transfer", proof: upload("virement.pdf", "%PDF-1.4 test", "application/pdf"))
    expect(AgentPayment.last.proof.blob.content_type).to eq("application/pdf")
  end

  it "does not pay an agent of another store" do
    other = Store.create!(slug: "ot-#{SecureRandom.hex(5)}", name: "Other", currency: "MAD")
    foreign = other.users.create!(name: "Foreign", email: "f-#{SecureRandom.hex(4)}@example.test", password: password, admin: false, confirmation_role: "agent", pay_per_delivery_cents: 800)
    sign_in(owner)
    pay(agent: foreign)
    expect(response).to have_http_status(:not_found)
    expect(AgentPayment.count).to eq(0)
  end
end
