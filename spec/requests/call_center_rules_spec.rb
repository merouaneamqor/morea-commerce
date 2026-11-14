require "rails_helper"
require "nokogiri"

RSpec.describe "Call center rules", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:password) { "synthetic-password-123" }
  let(:store) { Store.create!(slug: "rules-#{SecureRandom.hex(5)}", name: "Rules", currency: "MAD") }
  let(:owner) { store.users.create!(name: "Owner", email: "owner-#{SecureRandom.hex(4)}@example.test", password: password, admin: true) }
  let(:agent) { store.users.create!(name: "Saida", email: "saida-#{SecureRandom.hex(4)}@example.test", password: password, admin: false, confirmation_role: "agent", pay_per_delivery_cents: 1_000) }
  let!(:product) { store.products.create!(name: "Tracksuit", price_cents: 20_000, status: "active", track_inventory: true, stock: 50) }

  def make_order(phone: "0612345678", name: "Karim")
    editor = Orders::Editor.new(store: store, user: owner, external_effects: false)
    editor.create(name: name, phone: phone, city: "Casablanca", address: "Rue 1", lines: [ { product_id: product.id, quantity: 1 } ]) || raise(editor.errors.full_messages.to_sentence)
  end

  def sign_in(user)
    host! "#{store.slug}.#{Store.base_domain}"
    post "/admin/login", params: { email: user.email, password: password }
  end

  def clock_in(user) = ConfirmationShift.create!(store: store, user: user, started_at: 1.hour.ago)
  def document = Nokogiri::HTML(response.body)
  def confirmation_of(order) = order.reload.order_confirmation
  def json = JSON.parse(response.body)

  describe "claim expiry" do
    let!(:order) { make_order }

    before { clock_in(agent) }

    it "releases a claim after 15 minutes without activity, with a line in the history" do
      sign_in(agent)
      travel_to(Time.zone.local(2026, 11, 5, 10, 0)) do
        post "/admin/confirmations/#{order.id}/claim"
        travel 14.minutes
        Confirmations::ClaimExpiry.release_idle!(store)
        expect(confirmation_of(order).assigned_user_id).to eq(agent.id)

        travel 2.minutes
        Confirmations::ClaimExpiry.release_idle!(store)
        expect(confirmation_of(order).assigned_user_id).to be_nil
        expect(order.order_events.pluck(:body)).to include("Claim released automatically after 15 minutes without activity")
      end
    end

    it "keeps a claim alive while the call panel pings" do
      sign_in(agent)
      travel_to(Time.zone.local(2026, 11, 5, 10, 0)) do
        post "/admin/confirmations/#{order.id}/call", headers: { "ACCEPT" => "application/json" }
        travel 10.minutes
        post "/admin/confirmations/#{order.id}/touch_call", headers: { "ACCEPT" => "application/json" }
        travel 10.minutes
        Confirmations::ClaimExpiry.release_idle!(store)
        expect(confirmation_of(order).assigned_user_id).to eq(agent.id)
      end
    end

    it "makes an agent who comes back after 15 minutes find the order released, not act on a stale claim" do
      sign_in(agent)
      travel_to(Time.zone.local(2026, 11, 5, 10, 0)) do
        post "/admin/confirmations/#{order.id}/call", headers: { "ACCEPT" => "application/json" }
        travel 16.minutes
        post "/admin/confirmations/#{order.id}/finish_call", headers: { "ACCEPT" => "application/json" }, params: { outcome: "confirmed" }
        expect(response).to have_http_status(:unprocessable_content)
        expect(order.reload.status).to eq("new")
        expect(confirmation_of(order).assigned_user_id).to be_nil
      end
    end

    it "releases what the agent holds when she clocks out" do
      sign_in(agent)
      post "/admin/confirmations/#{order.id}/claim"
      expect(confirmation_of(order).assigned_user_id).to eq(agent.id)

      post "/admin/confirmations/clock_out"

      expect(confirmation_of(order).assigned_user_id).to be_nil
      expect(order.order_events.pluck(:body)).to include("Claim released: the agent clocked out")
    end

    it "lets an owner release it by hand, but not an agent" do
      sign_in(agent)
      post "/admin/confirmations/#{order.id}/claim"
      post "/admin/confirmations/#{order.id}/force_release"
      expect(confirmation_of(order).assigned_user_id).to eq(agent.id)

      sign_in(owner)
      post "/admin/confirmations/#{order.id}/force_release"
      expect(confirmation_of(order).assigned_user_id).to be_nil
      expect(order.order_events.last.body).to eq("Claim released by Owner (held by Saida)")
    end
  end

  describe "Numéro erroné" do
    let!(:order) { make_order }

    def flag_wrong_number
      clock_in(agent)
      sign_in(agent)
      post "/admin/confirmations/#{order.id}/call", headers: { "ACCEPT" => "application/json" }
      post "/admin/confirmations/#{order.id}/finish_call", headers: { "ACCEPT" => "application/json" }, params: { outcome: "wrong_number" }
      sign_in(owner)
    end

    it "has its own card with a counter on the owner side, and opens the list of those orders" do
      flag_wrong_number

      get "/admin/orders"
      expect(document.at_css("[data-card=wrong]")["data-value"]).to eq("1")

      get "/admin/orders", params: { confirmation: "wrong" }
      expect(document.css("[data-order-row]").map { |row| row["data-order-row"] }).to eq([ order.number ])
      get "/admin/orders", params: { group: "wrong_number" }
      expect(document.css("[data-order-row]").map { |row| row["data-order-row"] }).to eq([ order.number ])
    end

    it "lets the manager fix the number and send the order back to the queue" do
      flag_wrong_number

      post "/admin/confirmations/#{order.id}/requeue", params: { phone: "0698765432" }

      expect(order.reload.customer_phone).to end_with("698765432")
      expect(confirmation_of(order).disposition).to eq("pending")
      get "/admin/confirmations", params: { filter: "available" }
      expect(document.text).to include("##{order.number}")
    end

    it "refuses an invalid corrected number and keeps the order flagged" do
      flag_wrong_number

      post "/admin/confirmations/#{order.id}/requeue", params: { phone: "12" }

      expect(confirmation_of(order).disposition).to eq("wrong_number")
    end

    it "lets the manager cancel it from the tab, and agents cannot send it back" do
      flag_wrong_number
      patch "/admin/orders/#{order.id}/transition", params: { to_status: "cancelled", cancel_reason: "Wrong number" }
      expect(order.reload.status).to eq("cancelled")

      other = make_order(phone: "0611111111")
      clock_in(agent) unless ConfirmationShift.open.exists?(user: agent)
      sign_in(agent)
      post "/admin/confirmations/#{other.id}/call", headers: { "ACCEPT" => "application/json" }
      post "/admin/confirmations/#{other.id}/finish_call", headers: { "ACCEPT" => "application/json" }, params: { outcome: "wrong_number" }
      post "/admin/confirmations/#{other.id}/requeue", params: { phone: "0698765432" }
      expect(confirmation_of(other).disposition).to eq("wrong_number")
    end
  end

  describe "blocked numbers" do
    let!(:order) { make_order }

    before { clock_in(agent) }

    it "needs a reason, from an agent who is clocked in" do
      sign_in(agent)

      post "/admin/confirmations/#{order.id}/block_number", params: { reason: " " }
      expect(BlockedPhone.count).to eq(0)

      post "/admin/confirmations/#{order.id}/block_number", params: { reason: "Insults on the phone" }
      expect(BlockedPhone.where(store: store).sole).to have_attributes(reason: "Insults on the phone", blocked_by_id: agent.id, phone_key: "612345678")
      expect(confirmation_of(order).disposition).to eq("blocked")
    end

    it "keeps a new order from that number out of the queue, whatever the phone format" do
      BlockedPhone.block!(store: store, phone: "+212 612 34 56 78", reason: "Fraud", user: owner)

      blocked = make_order(phone: "0612345678", name: "Again")

      expect(confirmation_of(blocked).disposition).to eq("blocked")
      sign_in(owner)
      get "/admin/orders", params: { group: "blocked" }
      expect(document.css("[data-order-row]").map { |row| row["data-order-row"] }).to eq([ blocked.number ])
      sign_in(agent)
      get "/admin/confirmations", params: { filter: "available" }
      expect(document.text).not_to include("##{blocked.number}")
    end

    it "does not block another store's number" do
      foreign = Store.create!(slug: "foreign-#{SecureRandom.hex(4)}", name: "Other", currency: "MAD")
      BlockedPhone.block!(store: foreign, phone: "0612345678", reason: "Fraud", user: nil)

      expect(confirmation_of(make_order)&.disposition).not_to eq("blocked")
    end

    it "can be unblocked by an owner only; its orders go back to the queue" do
      BlockedPhone.block!(store: store, phone: "0612345678", reason: "Fraud", user: owner)
      blocked = make_order(phone: "0612345678", name: "Again")

      sign_in(agent)
      post "/admin/confirmations/#{blocked.id}/unblock"
      expect(confirmation_of(blocked).disposition).to eq("blocked")

      sign_in(owner)
      post "/admin/confirmations/#{blocked.id}/unblock"
      expect(BlockedPhone.count).to eq(0)
      expect(confirmation_of(blocked).disposition).to eq("pending")
    end
  end

  describe "WhatsApp" do
    let!(:order) { make_order }

    it "needs a shift, then logs who and when and opens WhatsApp with a ready message" do
      sign_in(agent)
      post "/admin/confirmations/#{order.id}/whatsapp"
      expect(order.order_events.where(kind: "whatsapp").count).to eq(0)

      clock_in(agent)
      post "/admin/confirmations/#{order.id}/whatsapp"

      expect(response).to have_http_status(:redirect)
      expect(response.location).to start_with("https://wa.me/212612345678?text=")
      expect(CGI.unescape(response.location)).to include("Karim", order.number)
      event = order.order_events.where(kind: "whatsapp").sole
      expect(event.user).to eq(agent)
      expect(event.body).to eq("WhatsApp opened by Saida")
    end
  end

  describe "deductions for returned orders" do
    def confirm_as_agent(order)
      clock_in(agent) unless ConfirmationShift.open.exists?(user: agent)
      sign_in(agent)
      post "/admin/confirmations/#{order.id}/call", headers: { "ACCEPT" => "application/json" }
      post "/admin/confirmations/#{order.id}/finish_call", headers: { "ACCEPT" => "application/json" }, params: { outcome: "confirmed" }
    end

    it "creates one pending deduction frozen at the agent's penalty when a confirmed order is returned" do
      agent.update!(return_penalty_cents: 5_000)
      order = make_order
      confirm_as_agent(order)

      order.reload.move_to_status!("returned", user: owner)
      agent.update!(return_penalty_cents: 9_000) # a later change does not rewrite it

      expect(AgentDeduction.where(store: store).sole).to have_attributes(user_id: agent.id, amount_cents: 5_000, status: "pending", order_id: order.id)
      expect(Team::AgentEarnings.new(store: store, range: 1.day.ago..1.day.from_now).summary_for(agent).pending_deductions).to eq(5_000)
    end

    it "creates nothing when the penalty is 0" do
      order = make_order
      confirm_as_agent(order)

      order.reload.move_to_status!("returned", user: owner)

      expect(AgentDeduction.count).to eq(0)
    end

    it "is subtracted at the next payout, oldest first and never split" do
      agent.update!(return_penalty_cents: 5_000)
      orders = 2.times.map { |i| make_order(phone: "061234567#{i}") }
      orders.each { |o| confirm_as_agent(o) }
      # 3 delivered orders at 10,00 would settle 30,00: only the deductions that fit are taken.
      orders.each { |o| o.reload.move_to_status!("returned", user: owner) }
      AgentDeduction.update_all(created_at: 1.day.ago) # both pending
      third = Array.new(8) { |i| make_order(phone: "06222222#{format('%02d', i)}") }
      third.each { |o| confirm_as_agent(o); o.reload.update_columns(status: "delivered", delivered_at: Time.current) }

      sign_in(owner)
      post "/admin/staff/#{agent.id}/pay"

      payment = AgentPayment.where(store: store, user: agent).sole
      expect(payment.amount_cents).to eq(8_000)          # 8 delivered x 10,00
      expect(payment.deductions_cents).to eq(5_000)      # one deduction fits (50,00); the second would exceed
      expect(payment.cash_cents).to eq(3_000)
      expect(AgentDeduction.pending.count).to eq(1)
      expect(AgentDeduction.where(status: "applied").sole.agent_payment_id).to eq(payment.id)
    end
  end
end
