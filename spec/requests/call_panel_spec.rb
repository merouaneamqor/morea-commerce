require "rails_helper"
require "nokogiri"

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

  def json = JSON.parse(response.body)
  def confirmation = order.reload.order_confirmation

  it "starts the call without a clock-in: claims the order and starts the server clock" do
    sign_in(agent)

    post "/admin/confirmations/#{order.id}/call", headers: { "ACCEPT" => "application/json" }

    expect(response).to have_http_status(:ok)
    expect(confirmation).to have_attributes(assigned_user_id: agent.id, call_started_at: be_present)
  end

  it "locks the order to the agent who opened it: a second agent cannot open it" do
    sign_in(agent)
    post "/admin/confirmations/#{order.id}/call", headers: { "ACCEPT" => "application/json" }
    sign_in(other)

    post "/admin/confirmations/#{order.id}/call", headers: { "ACCEPT" => "application/json" }

    expect(response).to have_http_status(:unprocessable_content)
    expect(json["error"]).to eq("Another agent has claimed this order.")
    post "/admin/confirmations/#{order.id}/finish_call", headers: { "ACCEPT" => "application/json" }, params: { outcome: "confirmed" }
    expect(order.reload.status).to eq("new")
    expect(confirmation.assigned_user_id).to eq(agent.id)
  end

  it "cannot finish a call without a result" do
    sign_in(agent)
    post "/admin/confirmations/#{order.id}/call", headers: { "ACCEPT" => "application/json" }

    post "/admin/confirmations/#{order.id}/finish_call", headers: { "ACCEPT" => "application/json" }, params: { outcome: "" }

    expect(response).to have_http_status(:unprocessable_content)
    expect(json["error"]).to eq("Pick the result of the call.")
    expect(ConfirmationAttempt.where(store: store).count).to eq(0)
    post "/admin/confirmations/#{order.id}/finish_call", headers: { "ACCEPT" => "application/json" }, params: { outcome: "abandoned" }
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "needs a reason to cancel" do
    sign_in(agent)
    post "/admin/confirmations/#{order.id}/call", headers: { "ACCEPT" => "application/json" }

    post "/admin/confirmations/#{order.id}/finish_call", headers: { "ACCEPT" => "application/json" }, params: { outcome: "cancelled", notes: " " }

    expect(json["error"]).to eq("Give a reason to cancel the order.")
    expect(order.reload.status).to eq("new")

    post "/admin/confirmations/#{order.id}/finish_call", headers: { "ACCEPT" => "application/json" }, params: { outcome: "cancelled", notes: "Customer changed their mind" }
    expect(response).to have_http_status(:ok)
    expect(order.reload.status).to eq("cancelled")
  end

  it "saves the result, adds one call attempt and stores the measured duration" do
    sign_in(agent)
    travel_to(Time.zone.local(2026, 11, 5, 10, 0, 0)) do
      post "/admin/confirmations/#{order.id}/call", headers: { "ACCEPT" => "application/json" }
      travel 83.seconds
      post "/admin/confirmations/#{order.id}/finish_call", headers: { "ACCEPT" => "application/json" }, params: { outcome: "confirmed", notes: "OK" }

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
    sign_in(agent)
    post "/admin/confirmations/#{order.id}/call", headers: { "ACCEPT" => "application/json" }

    post "/admin/confirmations/#{order.id}/finish_call", headers: { "ACCEPT" => "application/json" }, params: {
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

  it "cancels with a reason even when the order form would refuse the edits sent with it (they are ignored for a cancellation)" do
    sign_in(agent)
    post "/admin/confirmations/#{order.id}/call", headers: { "ACCEPT" => "application/json" }

    post "/admin/confirmations/#{order.id}/finish_call", headers: { "ACCEPT" => "application/json" }, params: {
      outcome: "cancelled", notes: "par client",
      order: { name: "Karim", phone: "0612345678", city: "Casablanca", address: "Rue 1", lines: {} }       # no product: the editor would refuse a total of 0
    }

    expect(response).to have_http_status(:ok), response.body
    expect(order.reload.status).to eq("cancelled")
    expect(order.order_events.where(kind: "edited")).to be_empty
    expect(confirmation.confirmation_attempts.last).to have_attributes(outcome: "cancelled", notes: "par client")
  end

  it "refuses edits that bring the total to 0 and keeps the order and the attempt untouched" do
    sign_in(agent)
    post "/admin/confirmations/#{order.id}/call", headers: { "ACCEPT" => "application/json" }

    post "/admin/confirmations/#{order.id}/finish_call", headers: { "ACCEPT" => "application/json" }, params: { outcome: "confirmed", order: { name: "Karim", phone: "0612345678", city: "Casablanca", address: "Rue 1", lines: {} } }

    expect(response).to have_http_status(:unprocessable_content)
    expect(order.reload.status).to eq("new")
    expect(order.order_items.sole.quantity).to eq(1)
    expect(ConfirmationAttempt.where(store: store).count).to eq(0)
  end

  it "counts a closed panel as one attempt only after more than 5 seconds, without changing the order" do
    sign_in(agent)
    travel_to(Time.zone.local(2026, 11, 5, 10, 0, 0)) do
      post "/admin/confirmations/#{order.id}/call", headers: { "ACCEPT" => "application/json" }
      travel 4.seconds
      post "/admin/confirmations/#{order.id}/abandon_call", headers: { "ACCEPT" => "application/json" }
      expect(ConfirmationAttempt.where(store: store).count).to eq(0)

      post "/admin/confirmations/#{order.id}/call", headers: { "ACCEPT" => "application/json" }
      travel 6.seconds
      post "/admin/confirmations/#{order.id}/abandon_call", headers: { "ACCEPT" => "application/json" }
    end

    expect(ConfirmationAttempt.where(store: store).sole).to have_attributes(outcome: "abandoned", call_seconds: 6)
    expect(order.reload.status).to eq("new")
    expect(confirmation).to have_attributes(call_started_at: nil, assigned_user_id: agent.id)
    expect(Confirmations::AgentHome.new(store: store, user: agent, range: 1.day.ago..1.day.from_now).points).to eq(0)
  end

  it "records a wrong number: the order stays new and leaves the queue" do
    sign_in(agent)
    post "/admin/confirmations/#{order.id}/call", headers: { "ACCEPT" => "application/json" }

    post "/admin/confirmations/#{order.id}/finish_call", headers: { "ACCEPT" => "application/json" }, params: { outcome: "wrong_number" }

    expect(response).to have_http_status(:ok)
    expect(order.reload.status).to eq("new")
    expect(confirmation.disposition).to eq("wrong_number")
    get "/admin/confirmations", params: { filter: "available" }
    expect(response.body).not_to include("##{order.number}")
  end

  it "returns the next order of the queue to open automatically" do
    second = Orders::Editor.new(store: store, user: owner, external_effects: false)
      .create(name: "Salma", phone: "0612345679", city: "Fès", address: "Rue 3", lines: [ { product_id: product.id, quantity: 1 } ])
    sign_in(agent)
    post "/admin/confirmations/#{order.id}/call", headers: { "ACCEPT" => "application/json" }

    post "/admin/confirmations/#{order.id}/finish_call", headers: { "ACCEPT" => "application/json" }, params: { outcome: "no_answer" }

    expect(json["next_order_id"]).to eq(order.id).or eq(second.id)
    expect(json["next_order_id"]).not_to be_nil
  end

  describe "the call window" do
    def page = Nokogiri::HTML(response.body)

    it "opens in the order-modal frame with the customer, the products, the timer and the five results" do
      sign_in(agent)
      get "/admin/confirmations/#{order.id}/panel", headers: { "Turbo-Frame" => "order-modal" }

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("data-seller-shell")
      dialog = page.at_css("turbo-frame#order-modal [data-call-panel][role=dialog]")
      expect(dialog["data-call-panel-call-url-value"]).to eq("/admin/confirmations/#{order.id}/call")
      expect(dialog["data-call-panel-finish-url-value"]).to eq("/admin/confirmations/#{order.id}/finish_call")
      expect(dialog.at_css("[data-call-panel-target=timer]").text).to eq("00:00")
      expect(dialog.at_css("input[name='order[name]']")["value"]).to eq("Karim")
      expect(dialog.at_css("input[name='order[phone]']")["value"]).to end_with("612345678")
      expect(dialog.at_css("a[href^='tel:']")).to be_present
      expect(dialog.at_css("input[name='order[lines][0][quantity]']")["value"]).to eq("1")
      expect(dialog.at_css("[data-call-panel-target=total]").text).to include("230")                         # 200 + 30
      outcomes = dialog.css("[data-call-panel-outcome-param]").map { |button| button["data-call-panel-outcome-param"] }
      expect(outcomes).to eq(%w[callback confirmed cancelled no_answer wrong_number])
      expect(dialog.at_css("[data-action='call-panel#askCallback']")).to be_present
    end

    it "offers the variants of the product to change the colour or size" do
      variant = product.product_variants.create!(name: "Rouge", price_cents: 21_000, stock: 5, active: true)
      product.product_variants.create!(name: "Bleu", price_cents: 22_000, stock: 5, active: true)
      order.order_items.first.update_columns(product_variant_id: variant.id)
      sign_in(owner)
      get "/admin/confirmations/#{order.id}/panel", headers: { "Turbo-Frame" => "order-modal" }

      select = page.at_css("select[name='order[lines][0][product_variant_id]']")
      expect(select.css("option").map { |option| [ option.text.strip, option["data-price-cents"] ] }).to eq([ [ "Rouge", "21000" ], [ "Bleu", "22000" ] ])
      expect(select.at_css("option[selected]").text.strip).to eq("Rouge")
    end

    it "sends an order that can no longer be called back to the queue" do
      order.update_columns(status: "cancelled")
      sign_in(owner)

      get "/admin/confirmations/#{order.id}/panel", headers: { "Turbo-Frame" => "order-modal" }

      expect(response).to redirect_to("/admin/confirmations/center")
    end

    it "is only for this store's orders" do
      other_store = Store.create!(slug: "call-o-#{SecureRandom.hex(4)}", name: "Other", currency: "MAD")
      foreign = other_store.orders.create!(customer: other_store.customers.create!(name: "A", phone: "0611111111"), number: "X1", status: "new", currency: "MAD", customer_name: "A", customer_phone: "0611111111", customer_city: "Fès", customer_address: "a", subtotal_cents: 100, total_cents: 100)
      sign_in(owner)

      get "/admin/confirmations/#{foreign.id}/panel", headers: { "Turbo-Frame" => "order-modal" }

      expect(response).to have_http_status(:not_found)
    end

    it "is the target of the Appeler button of the queue" do
      sign_in(agent)
      get "/admin/confirmations/center", params: { tab: "pending" }

      link = page.at_css("a[data-call='#{order.id}']")
      expect(link["href"]).to eq("/admin/confirmations/#{order.id}/panel")
      expect(link["data-turbo-frame"]).to eq("order-modal")
    end
  end
end
