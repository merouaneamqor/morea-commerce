require "rails_helper"

RSpec.describe Confirmations::Assignments do
  include ActiveSupport::Testing::TimeHelpers

  let(:store) { Store.create!(slug: "as-#{SecureRandom.hex(5)}", name: "Assign", currency: "MAD") }
  let(:owner) { store.users.create!(name: "Owner", email: "owner-#{SecureRandom.hex(4)}@example.test", password: "synthetic-password-123", admin: true) }
  let!(:saida) { store.users.create!(name: "Saida", email: "saida-#{SecureRandom.hex(4)}@example.test", password: "synthetic-password-123", admin: false, confirmation_role: "agent") }
  let!(:omar) { store.users.create!(name: "Omar", email: "omar-#{SecureRandom.hex(4)}@example.test", password: "synthetic-password-123", admin: false, confirmation_role: "agent") }
  let(:customer) { store.customers.create!(name: "Client", phone: "0612345678") }
  let(:service) { described_class.new(store: store, user: owner) }

  def make(number, minutes_ago: 60, status: "new", disposition: nil, attributed: nil, sendit: nil)
    record = store.orders.create!(customer: customer, number: number, status: "new", currency: "MAD", customer_name: "Client #{number}", customer_phone: "0612345678",
      customer_city: "Fès", customer_address: "Rue 1", subtotal_cents: 20_000, total_cents: 20_000)
    record.update_columns(status: status, created_at: minutes_ago.minutes.ago, sendit_code: sendit)
    OrderConfirmation.create!(store: store, order: record, disposition: disposition || "pending", attributed_user: attributed, callback_at: (1.day.from_now if disposition == "callback")) if disposition || attributed
    record
  end

  def clock_in(user) = ConfirmationShift.create!(store: store, user: user, started_at: 1.hour.ago)
  def attempt(order, user, outcome, at: Time.current)
    confirmation = OrderConfirmation.find_or_create_by!(store: store, order: order) { |row| row.disposition = "pending" }
    ConfirmationAttempt.create!(store: store, order_confirmation: confirmation, user: user, outcome: outcome).update_columns(created_at: at)
  end

  describe "the orders waiting for a call" do
    before do
      make("W1", minutes_ago: 50)
      make("W2", minutes_ago: 40, disposition: "no_answer")
      make("W3", minutes_ago: 30, disposition: "callback")
      make("B1", minutes_ago: 20, disposition: "blocked")                 # not waiting: blocked number
      make("X1", minutes_ago: 20, disposition: "wrong_number")            # not waiting: wrong number
      make("S1", minutes_ago: 20, sendit: "SEND123")                      # not waiting: already with the carrier
      make("D1", minutes_ago: 20, status: "confirmed")                    # not waiting: confirmed
      make("A1", minutes_ago: 10, attributed: omar)                       # waiting, but for Omar
    end

    it "lists the unattributed ones by default, newest first, and counts the attributed ones for each agent" do
      expect(service.rows.map(&:number)).to eq(%w[W3 W2 W1])
      expect(service.unattributed_count).to eq(3)
      expect(service.loads).to eq(omar.id => 1)
      expect(service.total).to eq(3)
    end

    it "filters by agent, by status, by missed calls, and sorts oldest first" do
      expect(described_class.new(store: store, params: { agent: omar.id.to_s }).rows.map(&:number)).to eq([ "A1" ])
      expect(described_class.new(store: store, params: { agent: "all" }).rows.map(&:number)).to eq(%w[A1 W3 W2 W1])
      expect(described_class.new(store: store, params: { status: "no_answer" }).rows.map(&:number)).to eq([ "W2" ])
      expect(described_class.new(store: store, params: { status: "callback" }).rows.map(&:number)).to eq([ "W3" ])
      expect(described_class.new(store: store, params: { status: "pending" }).rows.map(&:number)).to eq([ "W1" ])
      expect(described_class.new(store: store, params: { sort: "oldest" }).rows.map(&:number)).to eq(%w[W1 W2 W3])
      attempt(store.orders.find_by!(number: "W2"), saida, "no_answer")
      expect(described_class.new(store: store, params: { missed: "1" }).rows.map(&:number)).to eq([ "W2" ])
      expect(described_class.new(store: store, params: { q: "w3" }).rows.map(&:number)).to eq([ "W3" ])
    end

    it "pages the list and ignores a page size that is not offered" do
      listed = described_class.new(store: store, params: { per: "10", agent: "all" })
      expect(listed.per_page).to eq(10)
      expect(described_class.new(store: store, params: { per: "7" }).per_page).to eq(25)
      expect(described_class.new(store: store, params: { agent: "99999999" }).agent_filter).to eq("none")        # an unknown agent falls back to the default
    end
  end

  describe "#assign!" do
    let!(:order) { make("W1") }

    it "attributes the order to an agent, writes who did it in the history, and can take the attribution away" do
      expect(service.assign!(order.id, saida.id, by: owner)).to eq(saida)

      confirmation = order.reload.order_confirmation
      expect(confirmation).to have_attributes(attributed_user_id: saida.id, attributed_at: be_present)
      expect(order.order_events.last.body).to eq("Assigned to Saida by Owner")

      service.assign!(order.id, "", by: owner)
      expect(confirmation.reload).to have_attributes(attributed_user_id: nil, attributed_at: nil)
      expect(order.order_events.last.body).to eq("Assignment removed by Owner")
    end

    it "releases the claim of somebody else when the order is given to another agent, and keeps the claim of the new agent" do
      OrderConfirmation.create!(store: store, order: order, assigned_user: saida, claimed_at: Time.current, last_activity_at: Time.current)

      service.assign!(order.id, omar.id, by: owner)
      expect(order.reload.order_confirmation).to have_attributes(attributed_user_id: omar.id, assigned_user_id: nil, claimed_at: nil)

      order.order_confirmation.update!(assigned_user: omar, claimed_at: Time.current)
      service.assign!(order.id, omar.id, by: owner)
      expect(order.reload.order_confirmation.assigned_user_id).to eq(omar.id)
    end

    it "refuses someone who is not an agent of this store, and an order that is not waiting any more" do
      other_store = Store.create!(slug: "as-o-#{SecureRandom.hex(4)}", name: "Other", currency: "MAD")
      stranger = other_store.users.create!(name: "Stranger", email: "x-#{SecureRandom.hex(4)}@example.test", password: "synthetic-password-123", admin: false, confirmation_role: "agent")

      expect { service.assign!(order.id, stranger.id, by: owner) }.to raise_error(described_class::Error, /Choose an agent/)
      expect { service.assign!(order.id, owner.id, by: owner) }.to raise_error(described_class::Error, /Choose an agent/)           # the owner is not an agent
      order.update_columns(status: "confirmed")
      expect { service.assign!(order.id, saida.id, by: owner) }.to raise_error(described_class::Error, /no longer waiting/)
      expect(order.reload.order_confirmation&.attributed_user_id).to be_nil
    end
  end

  describe "#auto_assign!" do
    it "needs an agent on shift" do
      make("W1")

      expect { service.auto_assign!(by: owner) }.to raise_error(described_class::Error, /No agent is on shift/)
    end

    it "gives the oldest orders first, only to the agents on shift" do
      clock_in(saida)
      oldest = make("W1", minutes_ago: 90)
      newest = make("W2", minutes_ago: 10)

      result = service.auto_assign!(by: owner)

      expect(result).to include(assigned: 2, left: 0)
      expect(result[:per_agent]).to eq(saida => 2)
      expect([ oldest, newest ].map { |order| order.reload.order_confirmation.attributed_user_id }).to eq([ saida.id, saida.id ])
      expect(omar.id).not_to be_in(OrderConfirmation.where(store: store).pluck(:attributed_user_id))                                  # Omar is not on shift
      expect(oldest.order_events.last.body).to eq("Assigned to Saida automatically by Owner")
    end

    it "always picks the least loaded agent (ties go to the first one) so the work is spread evenly" do
      [ saida, omar ].each { |agent| clock_in(agent) }
      make("P1", minutes_ago: 200, attributed: omar)                       # Omar already has one
      %w[N1 N2 N3 N4 N5].each_with_index { |number, index| make(number, minutes_ago: 100 - index) }

      result = service.auto_assign!(by: owner)

      expect(result[:per_agent]).to eq(saida => 3, omar => 2)             # 0/1 -> A, A, B, A, B: everybody ends at 3
      expect(service.loads.values_at(saida.id, omar.id)).to eq([ 3, 3 ])
    end

    it "stops at the capacity of 20 and says how many orders are left without an agent" do
      clock_in(saida)
      22.times { |index| make("N#{index}", minutes_ago: 500 - index) }

      result = service.auto_assign!(by: owner)

      expect(result).to include(assigned: 20, left: 2)
      expect(described_class.new(store: store).loads[saida.id]).to eq(20)
    end

    it "does not touch what is already attributed" do
      clock_in(saida)
      taken = make("T1", attributed: omar)
      make("F1")

      service.auto_assign!(by: owner)

      expect(taken.reload.order_confirmation.attributed_user_id).to eq(omar.id)
    end
  end

  describe "the agent cards" do
    it "show the waiting orders of each agent, the calls of today, the success rate of the last 30 days and the load" do
      clock_in(saida)
      3.times { |index| make("A#{index}", attributed: saida) }
      done = make("C1", status: "confirmed")
      attempt(done, saida, "confirmed")
      attempt(done, saida, "confirmed")
      attempt(done, saida, "no_answer")
      attempt(done, saida, "cancelled")
      attempt(done, saida, "abandoned")                                         # not a call
      attempt(done, saida, "confirmed", at: 3.days.ago)                         # not today, but in the 30 days

      cards = described_class.new(store: store).agent_cards.to_h { |card| [ card[:user], card ] }

      expect(cards[saida]).to include(on_shift: true, pending: 3, today: 4, capacity: 20, load_percent: 15)
      expect(cards[saida][:success]).to eq(60.0)                                # 3 confirmed of 5 calls (no abandoned)
      expect(cards[omar]).to include(on_shift: false, pending: 0, today: 0, success: nil, load_percent: 0)
    end
  end

  describe "the queues" do
    let!(:mine) { make("M1", attributed: saida) }
    let!(:his) { make("H1", attributed: omar) }
    let!(:free) { make("F1") }
    let(:range) { DateRange.from_params({ from: Date.current.iso8601, to: Date.current.iso8601 }, today: Date.current) }

    def pending_for(user)
      Confirmations::CallCenter.new(store: store, user: user, range: range.time_range, params: { tab: "pending" }).rows.map(&:number).sort
    end

    it "show an agent the orders attributed to her and the free ones, never what is attributed to a colleague" do
      expect(pending_for(saida)).to eq(%w[F1 M1])
      expect(pending_for(omar)).to eq(%w[F1 H1])
    end

    it "show the owner everything" do
      expect(pending_for(owner)).to eq(%w[F1 H1 M1])
    end

    it "do not let an agent claim an order attributed to a colleague, but let the one it is for and the owner do it" do
      [ saida, omar ].each { |agent| clock_in(agent) }

      expect { Confirmations::Desk.new(store: store, user: saida).claim(his.id) }.to raise_error(Confirmations::Desk::Error, "This order is assigned to another agent.")
      expect(Confirmations::Desk.new(store: store, user: omar).claim(his.id).assigned_user_id).to eq(omar.id)
      expect(Confirmations::Desk.new(store: store, user: owner).claim(mine.id).assigned_user_id).to eq(owner.id)
    end
  end
end
