require "rails_helper"
require "nokogiri"

# The owner's Facturation page: what each agent is owed, and the payout with how it was made (cash or bank transfer), a reference and the proof.
RSpec.describe "Agent billing (owner)", type: :request do
  let(:password) { "synthetic-password-123" }
  let(:store) { Store.create!(slug: "bl-#{SecureRandom.hex(5)}", name: "Walkfit", currency: "MAD") }
  let!(:owner) { store.users.create!(name: "Owner", email: "owner-#{SecureRandom.hex(4)}@example.test", password: password, admin: true) }
  let!(:saida) { store.users.create!(name: "Saida", email: "saida-#{SecureRandom.hex(4)}@example.test", password: password, admin: false, confirmation_role: "agent", pay_per_delivery_cents: 800, return_penalty_cents: 300) }
  let!(:omar) { store.users.create!(name: "Omar", email: "omar-#{SecureRandom.hex(4)}@example.test", password: password, admin: false, confirmation_role: "agent", pay_per_delivery_cents: 800) }
  let(:customer) { store.customers.create!(name: "Client", phone: "0612345678") }
  let(:png) { Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==") }

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

  def delivered_for(agent, number, status: "delivered")
    order = store.orders.create!(customer: customer, number: number, status: status, currency: "MAD", customer_name: "Client", customer_phone: "0612345678",
      customer_city: "Fès", customer_address: "Rue 1", subtotal_cents: 20_000, total_cents: 20_000, confirmed_at: 3.days.ago, delivered_at: (2.days.ago if status == "delivered"))
    OrderConfirmation.create!(store: store, order: order, disposition: "confirmed", assigned_user: agent, claimed_at: 3.days.ago)
    order
  end

  before do
    delivered_for(saida, "P1")
    delivered_for(saida, "P2")
  end

  it "shows each agent what they are owed, and only to the owner" do
    sign_in(owner)
    get admin_agent_billing_path
    expect(response).to have_http_status(:ok)
    expect(page.at_css("[data-agent-row='#{saida.id}']")["data-unpaid"]).to eq("1600")
    expect(page.at_css("[data-agent-row='#{omar.id}'] [data-nothing-to-pay]")).to be_present
    expect(page.at_css("[data-pay-form='#{saida.id}'] input[name=payment_method][value=cash]")["checked"]).to be_present

    delete admin_logout_path rescue nil
    sign_in(saida)
    get admin_agent_billing_path
    expect(response).to redirect_to(admin_my_stats_path)
    post admin_agent_billing_pay_path(saida), params: { payment_method: "cash" }
    expect(AgentPayment.count).to eq(0)
  end

  it "pays in cash without a proof, deducting what a return cost, and refuses a second payment" do
    delivered_for(saida, "R1", status: "returned")
    AgentDeduction.create!(store: store, user: saida, order: store.orders.find_by!(number: "R1"), amount_cents: 300)
    sign_in(owner)

    post admin_agent_billing_pay_path(saida), params: { payment_method: "cash", reference: "Reçu 12" }
    expect(response).to redirect_to(admin_agent_billing_path)
    payment = AgentPayment.last
    expect(payment).to have_attributes(user_id: saida.id, paid_by_id: owner.id, amount_cents: 1600, deductions_cents: 300, payment_method: "cash", reference: "Reçu 12")
    expect(payment.cash_cents).to eq(1300)
    expect(payment.proof).not_to be_attached

    expect { post admin_agent_billing_pay_path(saida), params: { payment_method: "cash" } }.not_to change(AgentPayment, :count)
    expect(flash[:alert]).to be_present
  end

  it "needs a proof for a bank transfer, then keeps it with the payment and shows it to the owner and to the agent" do
    sign_in(owner)
    post admin_agent_billing_pay_path(saida), params: { payment_method: "bank_transfer", reference: "VIR-77" }
    expect(AgentPayment.count).to eq(0)
    expect(flash[:alert]).to include("Proof is required")

    post admin_agent_billing_pay_path(saida), params: { payment_method: "bank_transfer", reference: "VIR-77", proof: upload("virement.png", png, "image/png") }
    payment = AgentPayment.last
    expect(payment).to have_attributes(payment_method: "bank_transfer", reference: "VIR-77")
    expect(payment.proof).to be_attached

    get admin_agent_billing_path
    row = page.at_css("[data-payment='#{payment.id}']")
    expect(row["data-method"]).to eq("bank_transfer")
    expect(row.at_css("[data-proof-link]")["href"]).to include("/rails/active_storage/blobs")
    expect(row.text).to include("VIR-77")

    delete admin_logout_path rescue nil
    sign_in(saida)
    get admin_my_billing_path
    expect(page.at_css("[data-payment] a[href*='active_storage']")).to be_present
  end

  it "refuses an unknown method and a proof that is not an image or a PDF" do
    sign_in(owner)
    post admin_agent_billing_pay_path(saida), params: { payment_method: "crypto" }
    expect(AgentPayment.count).to eq(0)
    post admin_agent_billing_pay_path(saida), params: { payment_method: "bank_transfer", proof: upload("virement.txt", "hello", "text/plain") }
    expect(AgentPayment.count).to eq(0)
    expect(flash[:alert]).to include("PDF")
    post admin_agent_billing_pay_path(saida), params: { payment_method: "bank_transfer", proof: upload("virement.pdf", "%PDF-1.4 test", "application/pdf") }
    expect(AgentPayment.last.proof.blob.content_type).to eq("application/pdf")
  end

  it "does not pay an agent of another store" do
    other = Store.create!(slug: "ot-#{SecureRandom.hex(5)}", name: "Other", currency: "MAD")
    foreign = other.users.create!(name: "Foreign", email: "f-#{SecureRandom.hex(4)}@example.test", password: password, admin: false, confirmation_role: "agent", pay_per_delivery_cents: 800)
    sign_in(owner)
    post admin_agent_billing_pay_path(foreign), params: { payment_method: "cash" }
    expect(response).to have_http_status(:not_found)
    expect(AgentPayment.count).to eq(0)
  end
end
