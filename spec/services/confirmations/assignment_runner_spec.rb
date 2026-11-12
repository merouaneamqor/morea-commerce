require "rails_helper"

RSpec.describe Confirmations::AssignmentRunner do
  include ActiveSupport::Testing::TimeHelpers

  let(:now) { Time.zone.local(2026, 11, 12, 15, 0) }
  let(:store) { Store.create!(slug: "ar-#{SecureRandom.hex(5)}", name: "Rules", currency: "MAD") }
  let!(:saida) { store.users.create!(name: "Saida", email: "saida-#{SecureRandom.hex(4)}@example.test", password: "synthetic-password-123", admin: false, confirmation_role: "agent") }
  let!(:omar) { store.users.create!(name: "Omar", email: "omar-#{SecureRandom.hex(4)}@example.test", password: "synthetic-password-123", admin: false, confirmation_role: "agent") }
  let!(:hind) { store.users.create!(name: "Hind", email: "hind-#{SecureRandom.hex(4)}@example.test", password: "synthetic-password-123", admin: false, confirmation_role: "agent") }
  let(:customer) { store.customers.create!(name: "Client", phone: "0612345678") }

  before { travel_to(now) }
  after { travel_back }

  def clock_in(*agents) = agents.each { |agent| ConfirmationShift.create!(store: store, user: agent, started_at: 2.hours.ago) }

  def make(number, total: 20_000, minutes_ago: 5, attributed: nil, rule: nil, attributed_minutes_ago: nil, disposition: nil, callback_at: nil, call_started: false, status: "new")
    record = store.orders.create!(customer: customer, number: number, status: "new", currency: "MAD", customer_name: "Client #{number}", customer_phone: "0612345678",
      customer_city: "Fès", customer_address: "Rue 1", subtotal_cents: total, total_cents: total)
    record.update_columns(created_at: minutes_ago.minutes.ago, status: status)
    if attributed || disposition
      OrderConfirmation.create!(store: store, order: record, attributed_user: attributed, assignment_rule: rule, disposition: disposition || "pending", callback_at: callback_at,
        attributed_at: (attributed_minutes_ago.minutes.ago if attributed), call_started_at: (5.minutes.ago if call_started))
    end
    record
  end

  def rule!(name, agents:, percents: nil, **attrs)
    rule = store.assignment_rules.new(name: name, distribution: percents ? "percent" : "equal", **attrs)
    agents.each_with_index { |agent, index| rule.assignment_rule_agents.build(user: agent, percent: percents&.at(index)) }
    rule.save!
    rule
  end

  def owner_of(order) = order.reload.order_confirmation&.attributed_user
  def run(**options) = described_class.new(store: store, now: now).run!

  describe "giving new orders" do
    it "splits the orders 50/50 between two agents online: 10 orders, 5 each" do
      clock_in(saida, omar)
      rule!("Équitable", agents: [ saida, omar ])
      orders = (1..10).map { |i| make("E#{i}", minutes_ago: 100 - i) }

      expect(run).to eq(attributed: 10, transferred: 0)

      expect(orders.map { |order| owner_of(order) }.tally).to eq(saida => 5, omar => 5)
      expect(orders.first.reload.order_confirmation.assignment_rule).to be_present
      expect(orders.first.order_events.last.body).to eq("Assigned to Saida by the rule “Équitable”")
    end

    it "splits by percentage: 70 % and 30 % over 10 orders gives 7 and 3" do
      clock_in(saida, omar)
      rule!("70/30", agents: [ saida, omar ], percents: [ 70, 30 ])
      orders = (1..10).map { |i| make("P#{i}", minutes_ago: 100 - i) }

      run

      expect(orders.map { |order| owner_of(order) }.tally).to eq(saida => 7, omar => 3)
    end

    it "keeps the share over several runs: the orders of the next minute continue where the last ones stopped" do
      clock_in(saida, omar)
      rule!("Équitable", agents: [ saida, omar ])
      3.times { |i| make("A#{i}", minutes_ago: 50 - i) }
      run
      3.times { |i| make("B#{i}", minutes_ago: 10 - i) }
      run

      owners = store.orders.map { |order| owner_of(order) }
      expect(owners.tally).to eq(saida => 3, omar => 3)
    end

    it "only counts what the rule gave today: yesterday's orders do not unbalance the shares" do
      clock_in(saida, omar)
      rule = rule!("Équitable", agents: [ saida, omar ])
      4.times { |i| make("Y#{i}", attributed: saida, rule: rule, attributed_minutes_ago: 24 * 60 + 10 + i).update_columns(status: "confirmed") }
      first = make("T1")

      run

      expect(owner_of(first)).to eq(saida)                                      # 0 today for both: the first agent; with yesterday counted it would be Omar
    end

    it "only uses the agents who are online: an agent without an open shift gets nothing" do
      clock_in(saida)
      rule!("Équitable", agents: [ saida, omar ])
      orders = (1..4).map { |i| make("O#{i}", minutes_ago: 60 - i) }

      run

      expect(orders.map { |order| owner_of(order) }.uniq).to eq([ saida ])
    end

    it "leaves the order open to everybody when nobody of the rule is online" do
      clock_in(hind)
      rule!("Équitable", agents: [ saida, omar ])
      order = make("N1")

      expect(run).to eq(attributed: 0, transferred: 0)
      expect(owner_of(order)).to be_nil
    end

    it "does not give an agent more than her capacity of 20 waiting orders" do
      clock_in(saida, omar)
      rule = rule!("Équitable", agents: [ saida, omar ])
      20.times { |i| make("L#{i}", attributed: saida, rule: rule, attributed_minutes_ago: 1) }
      fresh = (1..3).map { |i| make("F#{i}", minutes_ago: 30 - i) }

      run

      expect(fresh.map { |order| owner_of(order) }).to eq([ omar, omar, omar ])    # Saida is full
    end

    it "picks the first active rule that matches, by priority: a big order goes to the VIP rule, the others to the general one" do
      clock_in(saida, omar, hind)
      rule!("VIP", agents: [ hind ], min_amount_cents: 50_000)
      rule!("Général", agents: [ saida, omar ])
      big = make("BIG", total: 60_000, minutes_ago: 20)
      exact = make("EDGE", total: 50_000, minutes_ago: 19)                      # the minimum is included
      small = make("SMALL", total: 49_999, minutes_ago: 18)

      run

      expect([ owner_of(big), owner_of(exact), owner_of(small) ]).to eq([ hind, hind, saida ])
    end

    it "ignores a rule that is switched off, and an order that is blocked, a wrong number, confirmed or already attributed" do
      clock_in(saida)
      off = rule!("Off", agents: [ omar ], active: false)
      rule!("On", agents: [ saida ])
      free = make("OK1")
      blocked = make("BL1", disposition: "blocked")
      wrong = make("WR1", disposition: "wrong_number")
      confirmed = make("CF1", status: "confirmed")
      mine = make("MI1", attributed: omar, attributed_minutes_ago: 1)

      run

      expect(owner_of(free)).to eq(saida)
      expect(free.order_confirmation.assignment_rule.name).to eq("On")
      expect([ blocked, wrong, confirmed ].map { |order| owner_of(order) }).to eq([ nil, nil, nil ])
      expect(owner_of(mine)).to eq(omar)
      expect(off.order_confirmations).to be_empty
    end

    it "leaves an order with a callback planned alone" do
      clock_in(saida)
      rule!("On", agents: [ saida ])
      planned = make("CB1", disposition: "callback", callback_at: 1.day.from_now)

      run

      expect(owner_of(planned)).to be_nil
    end

    it "does nothing without an active rule" do
      clock_in(saida)
      make("W1")

      expect(run).to eq(attributed: 0, transferred: 0)
    end
  end

  describe "the other ways to pick the agent" do
    # Saida has 3 of 4 calls confirmed in the last 30 days (75 %), Omar 1 of 2 (50 %), Hind never called.
    before do
      done = make("DONE", status: "confirmed")
      confirmation = OrderConfirmation.create!(store: store, order: done, disposition: "confirmed")
      { saida => %w[confirmed confirmed confirmed no_answer], omar => %w[confirmed cancelled] }.each do |agent, outcomes|
        outcomes.each { |outcome| ConfirmationAttempt.create!(store: store, order_confirmation: confirmation, user: agent, outcome: outcome) }
      end
    end

    it "gives the order to the agent with the fewest waiting orders (least loaded), the first agent on a tie" do
      clock_in(saida, omar)
      rule = rule!("Charge", agents: [ saida, omar ], distribution: "least_loaded")
      3.times { |i| make("S#{i}", attributed: saida, rule: rule, attributed_minutes_ago: 1) }
      make("O1", attributed: omar, rule: rule, attributed_minutes_ago: 1)
      fresh = (1..3).map { |i| make("N#{i}", minutes_ago: 30 - i) }

      run

      expect(fresh.map { |order| owner_of(order) }).to eq([ omar, omar, saida ])      # Omar 1 -> 2 -> 3, then 3 against 3: the first agent
    end

    it "gives the orders to the agent with the best success rate (best performance)" do
      clock_in(saida, omar)
      rule!("Perf", agents: [ saida, omar ], distribution: "best_performance")
      fresh = (1..3).map { |i| make("N#{i}", minutes_ago: 30 - i) }

      run

      expect(fresh.map { |order| owner_of(order) }).to eq([ saida, saida, saida ])    # 75 % against 50 %
    end

    it "leaves out the agents below the minimum success rate, and keeps an agent with no call yet eligible" do
      clock_in(saida, omar, hind)
      rule!("Seuil", agents: [ saida, omar, hind ], min_success_percent: 60)
      fresh = (1..6).map { |i| make("N#{i}", minutes_ago: 30 - i) }

      run

      expect(fresh.map { |order| owner_of(order) }.tally).to eq(saida => 3, hind => 3)   # Omar (50 %) is out, Hind has no rate yet
    end

    it "gives nothing when nobody reaches the minimum success rate" do
      clock_in(omar)
      rule!("Seuil", agents: [ omar ], min_success_percent: 60)
      order = make("N1")

      expect(run).to eq(attributed: 0, transferred: 0)
      expect(owner_of(order)).to be_nil
    end

    it "picks at random among the agents online and eligible, never an agent offline" do
      clock_in(saida, omar)
      rule!("Hasard", agents: [ saida, omar, hind ], distribution: "random")
      fresh = (1..30).map { |i| make("N#{i}", minutes_ago: 100 - i) }

      described_class.new(store: store, now: now, random: Random.new(7)).run!

      tally = fresh.map { |order| owner_of(order) }.tally
      expect(tally.keys).to contain_exactly(saida, omar)                              # Hind is offline
      expect(tally.values.sum).to eq(30)
      expect(tally.values.min).to be >= 8                                             # both get a real share
    end

    it "moves a late order with the same method: the least loaded other agent" do
      clock_in(saida, omar, hind)
      rule = rule!("Charge", agents: [ saida, omar, hind ], distribution: "least_loaded")
      2.times { |i| make("H#{i}", attributed: hind, rule: rule, attributed_minutes_ago: 1) }
      late = make("LT1", attributed: saida, rule: rule, attributed_minutes_ago: 40)

      run

      expect(owner_of(late)).to eq(omar)                                              # Omar has 0 waiting orders, Hind 2
    end
  end

  describe "moving a late order to an agent who is online" do
    let!(:rule) { rule!("Équitable", agents: [ saida, omar ]) }

    it "moves an order the agent did not confirm in 30 minutes to another agent of the rule, and says so in the history" do
      clock_in(saida, omar)
      late = make("LT1", attributed: saida, rule: rule, attributed_minutes_ago: 31)
      fresh = make("FR1", attributed: saida, rule: rule, attributed_minutes_ago: 29)

      expect(run.fetch(:transferred)).to eq(1)

      expect(owner_of(late)).to eq(omar)
      expect(late.order_confirmation.attributed_at).to be_within(1.second).of(now)                   # the 30 minutes start again
      expect(late.order_events.last.body).to eq("Moved from Saida to Omar: not confirmed within 30 minutes")
      expect(owner_of(fresh)).to eq(saida)                                                           # 29 minutes: still hers
    end

    it "uses the delay of the rule: 45 minutes keeps a 31-minute-old order where it is" do
      clock_in(saida, omar)
      rule.update!(timeout_minutes: 45)
      order = make("LT1", attributed: saida, rule: rule, attributed_minutes_ago: 31)

      run

      expect(owner_of(order)).to eq(saida)
    end

    it "frees the claim the slow agent was holding" do
      clock_in(saida, omar)
      order = make("LT1", attributed: saida, rule: rule, attributed_minutes_ago: 40)
      order.order_confirmation.update!(assigned_user: saida, claimed_at: 35.minutes.ago, last_activity_at: 35.minutes.ago)

      run

      expect(order.order_confirmation.reload).to have_attributes(attributed_user_id: omar.id, assigned_user_id: nil)
    end

    it "does not move it to an agent who is offline: the order waits where it is until somebody else is online" do
      clock_in(saida)
      order = make("LT1", attributed: saida, rule: rule, attributed_minutes_ago: 60)

      expect(run.fetch(:transferred)).to eq(0)
      expect(owner_of(order)).to eq(saida)

      clock_in(omar)
      expect(run.fetch(:transferred)).to eq(1)
      expect(owner_of(order)).to eq(omar)
    end

    it "goes to any other agent online when no other agent of the rule is" do
      clock_in(saida, hind)                                                  # Hind is not in the rule, Omar is offline
      order = make("LT1", attributed: saida, rule: rule, attributed_minutes_ago: 60)

      run

      expect(owner_of(order)).to eq(hind)
    end

    it "never moves a hand attribution, a callback, an order with a call in progress, or when the rule does not transfer" do
      clock_in(saida, omar)
      by_hand = make("HA1", attributed: saida, attributed_minutes_ago: 120)
      callback = make("CB1", attributed: saida, rule: rule, attributed_minutes_ago: 120, disposition: "callback", callback_at: 1.hour.from_now)
      on_call = make("OC1", attributed: saida, rule: rule, attributed_minutes_ago: 120, call_started: true)
      stay = rule!("Reste", agents: [ saida ], transfer_on_timeout: false)
      kept = make("KP1", attributed: saida, rule: stay, attributed_minutes_ago: 120)

      expect(run.fetch(:transferred)).to eq(0)

      expect([ by_hand, callback, on_call, kept ].map { |order| owner_of(order) }).to eq([ saida ] * 4)
    end

    it "does not move an order that is no longer waiting" do
      clock_in(saida, omar)
      order = make("DN1", attributed: saida, rule: rule, attributed_minutes_ago: 120, status: "confirmed")

      expect(run.fetch(:transferred)).to eq(0)
    end

    it "does not touch the orders of another store" do
      clock_in(saida, omar)
      other = Store.create!(slug: "ar-o-#{SecureRandom.hex(4)}", name: "Other", currency: "MAD")
      foreign = other.orders.create!(customer: other.customers.create!(name: "X", phone: "0611111111"), number: "F1", status: "new", currency: "MAD", customer_name: "X", customer_phone: "0611111111",
        customer_city: "Fès", customer_address: "a", subtotal_cents: 100, total_cents: 100)

      run

      expect(foreign.reload.order_confirmation).to be_nil
    end
  end

  describe AssignmentRulesJob do
    it "runs the rules of every store that has an active one" do
      clock_in(saida)
      rule!("On", agents: [ saida ])
      order = make("J1")

      described_class.perform_now

      expect(owner_of(order)).to eq(saida)
    end
  end
end
