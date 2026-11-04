require "rails_helper"

RSpec.describe "Call panel", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:password) { "synthetic-password-123" }
  let(:store) { Store.create!(slug: "call-#{SecureRandom.hex(5)}", name: "Call desk", currency: "MAD") }
  let(:owner) { store.users.create!(name: "Owner", email: "owner-#{SecureRandom.hex(4)}@example.test", password: password, admin: true) }
  let(:agent) { store.users.create!(name: "Saida", email: "saida-#{SecureRandom.hex(4)}@example.test", password: password, admin: false, confirmation_role: "agent") }
  let(:other) { store.users.create!(name: "Omar", email: "omar-#{SecureRandom.hex(4)}@example.test", password: password, admin: false, confirmation_role: "agent") }
  let!(:product) { store.products.create!(name: "Tracksuit", price_cents: 20_000, status: "active", track_inventory: true, stock: 50, cost_cents: 8_000) }
  let!(:order) do
    editor = Orders::Editor.new(store: store, user: owner, external_effects: false)
    editor.create(name: "Karim", phone: "0612345678", city: "Casablanca", address: "Rue 1", shipping_dh: 30, lines: [ { product_id: product.id, quantity: 1 } ]) || raise(editor.errors.full_messages.to_sentence)
  end

  def sign_in(user)
    host! "#{store.slug}.#{Store.base_domain}"
    post "/admin/login", params: { email: user.email, password: password }
  end

  def clock_in(user)
    ConfirmationShift.create!(store: store, user: user, started_at: 1.hour.ago)
  end

  def json = JSON.parse(response.body)
  def confirmation = order.reload.order_confirmation

  it "cannot start a call without clocking in, and the server says why" do
    sign_in(agent)

    post "/admin/confirmations/#{order.id}/call"

    expect(response).to have_http_status(:unprocessable_content)
    expect(json["error"]).to eq(I18n.t("admin.confirmations.clock_in_required"))
    expect(confirmation&.assigned_user_id).to be_nil
  end

  it "starts the call: claims the order and starts the server clock" do
    clock_in(agent)
    sign_in(agent)

    post "/admin/confirmations/#{order.id}/call"

    expect(response).to have_http_status(:ok)
    expect(confirmation).to have_attributes(assigned_user_id: agent.id, call_started_at: be_present)
  end

  it "locks the order to the agent who opened it: a second agent cannot open it" do
    [ agent, other ].each { |person| clock_in(person) }
    sign_in(agent)
    post "/admin/confirmations/#{order.id}/call"
    sign_in(other)

    post "/admin/confirmations/#{order.id}/call"

    expect(response).to have_http_status(:unprocessable_content)
    expect(json["error"]).to eq("Another agent has claimed this order.")
    post "/admin/confirmations/#{order.id}/finish_call", params: { outcome: "confirmed" }
    expect(order.reload.status).to eq("new")
    expect(confirmation.assigned_user_id).to eq(agent.id)
  end

  it "cannot finish a call without a result" do
    clock_in(agent)
    sign_in(agent)
    post "/admin/confirmations/#{order.id}/call"

    post "/admin/confirmations/#{order.id}/finish_call", params: { outcome: "" }

    expect(response).to have_http_status(:unprocessable_content)
    expect(json["error"]).to eq("Pick the result of the call.")
    expect(ConfirmationAttempt.where(store: store).count).to eq(0)
    post "/admin/confirmations/#{order.id}/finish_call", params: { outcome: "abandoned" }
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "needs a reason to cancel" do
    clock_in(agent)
    sign_in(agent)
    post "/admin/confirmations/#{order.id}/call"

    post "/admin/confirmations/#{order.id}/finish_call", params: { outcome: "cancelled", notes: " " }

    expect(json["error"]).to eq("Give a reason to cancel the order.")
    expect(order.reload.status).to eq("new")

    post "/admin/confirmations/#{order.id}/finish_call", params: { outcome: "cancelled", notes: "Customer changed their mind" }
    expect(response).to have_http_status(:ok)
    expect(order.reload.status).to eq("cancelled")
  end

  it "saves the result, adds one call attempt and stores the measured duration" do
    clock_in(agent)
    sign_in(agent)
    travel_to(Time.zone.local(2026, 11, 5, 10, 0, 0)) do
      post "/admin/confirmations/#{order.id}/call"
      travel 83.seconds
      post "/admin/confirmations/#{order.id}/finish_call", params: { outcome: "confirmed", notes: "OK" }

      expect(response).to have_http_status(:ok)
      attempt = ConfirmationAttempt.where(store: store).sole
      expect(attempt).to have_attributes(outcome: "confirmed", user_id: agent.id, call_seconds: 83)
      expect(order.reload.status).to eq("confirmed")
      expect(confirmation).to have_attributes(disposition: "confirmed", call_started_at: nil)
      # The measured duration feeds "Average time per order".
      home = Confirmations::AgentHome.new(store: store, user: agent, range: Time.current.beginning_of_day..Time.current.end_of_day)
      expect(home.average_handled_seconds).to eq(83)
    end
  end

  it "changing the quantity updates the total and the history says who changed what" do
    clock_in(agent)
    sign_in(agent)
    post "/admin/confirmations/#{order.id}/call"

    post "/admin/confirmations/#{order.id}/finish_call", params: {
      outcome: "confirmed",
      order: { name: "Karim", phone: "0612345678", second_phone: "0698765432", city: "Casablanca", address: "Rue 2",
               lines: { "0" => { product_id: product.id, quantity: 3 } } }
    }

    expect(response).to have_http_status(:ok), response.body
    order.reload
    expect(order.order_items.sole).to have_attributes(quantity: 3, total_cents: 60_000)
    expect(order.total_cents).to eq(63_000)  # 3 x 200,00 + 30,00 shipping
    expect(order.second_phone).to eq("+212698765432").or eq("0698765432")
    edit = order.order_events.where(kind: "edited").where("body LIKE 'Call edit:%'").sole
    expect(edit.user).to eq(agent)
    expect(edit.body).to include("1 × Tracksuit → 3 × Tracksuit", "address: Rue 1 → Rue 2", "total: 230.0 → 630.0 MAD")
  end

  it "refuses edits that bring the total to 0 and keeps the order and the attempt untouched" do
    clock_in(agent)
    sign_in(agent)
    post "/admin/confirmations/#{order.id}/call"

    post "/admin/confirmations/#{order.id}/finish_call", params: { outcome: "confirmed", order: { name: "Karim", phone: "0612345678", city: "Casablanca", address: "Rue 1", lines: {} } }

    expect(response).to have_http_status(:unprocessable_content)
    expect(order.reload.status).to eq("new")
    expect(order.order_items.sole.quantity).to eq(1)
    expect(ConfirmationAttempt.where(store: store).count).to eq(0)
  end

  it "counts a closed panel as one attempt only after more than 5 seconds, without changing the order" do
    clock_in(agent)
    sign_in(agent)
    travel_to(Time.zone.local(2026, 11, 5, 10, 0, 0)) do
      post "/admin/confirmations/#{order.id}/call"
      travel 4.seconds
      post "/admin/confirmations/#{order.id}/abandon_call"
      expect(ConfirmationAttempt.where(store: store).count).to eq(0)

      post "/admin/confirmations/#{order.id}/call"
      travel 6.seconds
      post "/admin/confirmations/#{order.id}/abandon_call"
    end

    expect(ConfirmationAttempt.where(store: store).sole).to have_attributes(outcome: "abandoned", call_seconds: 6)
    expect(order.reload.status).to eq("new")
    expect(confirmation).to have_attributes(call_started_at: nil, assigned_user_id: agent.id)
    expect(Confirmations::AgentHome.new(store: store, user: agent, range: 1.day.ago..1.day.from_now).points).to eq(0)
  end

  it "records a wrong number: the order stays new and leaves the queue" do
    clock_in(agent)
    sign_in(agent)
    post "/admin/confirmations/#{order.id}/call"

    post "/admin/confirmations/#{order.id}/finish_call", params: { outcome: "wrong_number" }

    expect(response).to have_http_status(:ok)
    expect(order.reload.status).to eq("new")
    expect(confirmation.disposition).to eq("wrong_number")
    get "/admin/confirmations", params: { filter: "available" }
    expect(response.body).not_to include("##{order.number}")
  end

  it "returns the next order of the queue to open automatically" do
    second = Orders::Editor.new(store: store, user: owner, external_effects: false)
      .create(name: "Salma", phone: "0612345679", city: "Fès", address: "Rue 3", lines: [ { product_id: product.id, quantity: 1 } ])
    clock_in(agent)
    sign_in(agent)
    post "/admin/confirmations/#{order.id}/call"

    post "/admin/confirmations/#{order.id}/finish_call", params: { outcome: "no_answer" }

    expect(json["next_order_id"]).to eq(order.id).or eq(second.id)
    expect(json["next_order_id"]).not_to be_nil
  end
end
