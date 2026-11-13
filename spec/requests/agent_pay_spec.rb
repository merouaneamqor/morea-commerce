require "rails_helper"

RSpec.describe "Agent pay and statistics", type: :request do
  let(:password) { "synthetic-password-123" }
  let(:store) { Store.create!(slug: "pay-#{SecureRandom.hex(5)}", name: "Synthetic workspace", currency: "MAD") }
  let(:admin) { store.users.create!(email: "owner-#{SecureRandom.hex(4)}@example.test", password: password, admin: true) }
  let(:agent) do
    store.users.create!(email: "agent-#{SecureRandom.hex(4)}@example.test", password: password,
                        confirmation_role: "agent", pay_per_delivery_cents: 800)
  end
  let(:customer) { store.customers.create!(name: "Synthetic buyer", phone: "0600000001", city: "Casablanca") }

  def sign_in(user)
    host! "#{store.slug}.#{Store.base_domain}"
    post "/admin/login", params: { email: user.email, password: password }
    expect(response).to have_http_status(:redirect)
  end

  # An order the agent confirmed by phone; `status` is whatever the courier reports since.
  def confirmed_order(status:, by: agent, delivered_at: nil)
    order = store.orders.create!(
      customer: customer, status: status, customer_name: "Synthetic buyer", customer_phone: "0600000001",
      customer_city: "Casablanca", customer_address: "1 Synthetic street", total_cents: 39_900, currency: "MAD",
      confirmed_at: Time.current, delivered_at: delivered_at
    )
    OrderConfirmation.create!(store: store, order: order, assigned_user: by, disposition: "confirmed", claimed_at: Time.current)
    order
  end

  let(:range) { Time.current.beginning_of_month..Time.current }
  subject(:earnings) { Team::AgentEarnings.new(store: store, range: range) }

  it "pays only for delivered orders the agent confirmed" do
    confirmed_order(status: "delivered", delivered_at: Time.current)
    confirmed_order(status: "delivered", delivered_at: Time.current)
    confirmed_order(status: "in_transit")
    confirmed_order(status: "returned")

    summary = earnings.summary_for(agent)
    expect(summary.figures.confirmed).to eq(4)
    expect(summary.figures.delivered).to eq(2)
    expect(summary.figures.in_delivery).to eq(1)
    expect(summary.figures.returned).to eq(1)
    expect(summary.earned_total).to eq(1_600)
    expect(summary.unpaid).to eq(1_600)
  end

  it "does not credit another agent's or another store's orders" do
    other = store.users.create!(email: "other-#{SecureRandom.hex(4)}@example.test", password: password,
                                confirmation_role: "agent", pay_per_delivery_cents: 800)
    confirmed_order(status: "delivered", by: other, delivered_at: Time.current)

    expect(earnings.summary_for(agent).earned_total).to eq(0)
    foreign = Team::AgentEarnings.new(store: Store.create!(slug: "x-#{SecureRandom.hex(4)}", name: "Other", currency: "MAD"), range: range)
    expect(foreign.summary_for(other).earned_total).to eq(0)
  end

  it "records one payment for the unpaid balance and refuses a second" do
    confirmed_order(status: "delivered", delivered_at: Time.current)
    sign_in(admin)

    expect { post pay_admin_user_path(agent) }.to change(AgentPayment, :count).by(1)
    payment = AgentPayment.last
    expect(payment).to have_attributes(store_id: store.id, user_id: agent.id, paid_by_id: admin.id, amount_cents: 800)

    expect { post pay_admin_user_path(agent) }.not_to change(AgentPayment, :count)
    expect(earnings.summary_for(agent).unpaid).to eq(0)
  end

  it "keeps agents out of the team page and shows them only their own statistics" do
    confirmed_order(status: "delivered", delivered_at: Time.current)
    sign_in(agent)

    get admin_users_path
    expect(response).to redirect_to(admin_my_stats_path)
    post pay_admin_user_path(agent)
    expect(AgentPayment.count).to eq(0)

    get admin_my_stats_path
    expect(response).to have_http_status(:ok)
    get admin_my_billing_path
    expect(response).to have_http_status(:ok)
    earned = Nokogiri::HTML(response.body).at_css("[data-kpi='earned_total'] [data-value]").text.squish.delete("⁦⁩")
    expect(earned).to eq("8 MAD")
  end

  it "renders the team, orders and customers pages for the owner" do
    confirmed_order(status: "delivered", delivered_at: Time.current)
    sign_in(admin)

    get admin_users_path
    expect(response).to have_http_status(:ok)
    get admin_orders_path(group: "delivered", agent_id: agent.id)
    expect(response).to have_http_status(:ok)
    get admin_customers_path(segment: "loyal")
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Synthetic buyer")
  end

  it "classifies customers by delivery history" do
    confirmed_order(status: "delivered", delivered_at: Time.current)
    segments = Customers::Segments.new(store)
    expect(segments.for(customer).segment).to eq("loyal")
    expect(segments.counts).to include("all" => 1, "loyal" => 1, "at_risk" => 0, "new" => 0)
  end
end
