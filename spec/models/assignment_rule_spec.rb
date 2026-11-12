require "rails_helper"

RSpec.describe AssignmentRule do
  let(:store) { Store.create!(slug: "am-#{SecureRandom.hex(5)}", name: "Rules", currency: "MAD") }
  let!(:saida) { store.users.create!(name: "Saida", email: "saida-#{SecureRandom.hex(4)}@example.test", password: "synthetic-password-123", admin: false, confirmation_role: "agent") }
  let!(:omar) { store.users.create!(name: "Omar", email: "omar-#{SecureRandom.hex(4)}@example.test", password: "synthetic-password-123", admin: false, confirmation_role: "agent") }

  def build(agents: [ saida, omar ], percents: nil, **attrs)
    rule = store.assignment_rules.new({ name: "Rule", distribution: percents ? "percent" : "equal" }.merge(attrs))
    agents.each_with_index { |agent, index| rule.assignment_rule_agents.build(user: agent, percent: percents&.at(index)) }
    rule
  end

  it "is valid with a name and agents, and gets the next priority" do
    first = build.tap(&:save!)
    second = build(name: "Second").tap(&:save!)

    expect([ first.position, second.position ]).to eq([ 1, 2 ])
    expect(store.assignment_rules.pluck(:name)).to eq(%w[Rule Second])
  end

  it "needs a name and at least one agent" do
    expect(build(name: "")).not_to be_valid
    empty = build(agents: [])
    expect(empty).not_to be_valid
    expect(empty.errors.full_messages.to_sentence).to include("Choose at least one agent")
  end

  it "needs the percentages to add up to exactly 100 when it splits by percentage" do
    expect(build(percents: [ 60, 40 ])).to be_valid
    off = build(percents: [ 60, 30 ])
    expect(off).not_to be_valid
    expect(off.errors.full_messages.to_sentence).to include("must add up to 100 % (now 90 %)")
    expect(build(percents: [ 100, 0 ])).to be_valid
    expect(build(percents: [ 50, 51 ])).not_to be_valid
  end

  it "only takes active confirmation agents of its own store" do
    other_store = Store.create!(slug: "am-o-#{SecureRandom.hex(4)}", name: "Other", currency: "MAD")
    stranger = other_store.users.create!(name: "Stranger", email: "x-#{SecureRandom.hex(4)}@example.test", password: "synthetic-password-123", admin: false, confirmation_role: "agent")
    supervisor = store.users.create!(name: "Boss", email: "b-#{SecureRandom.hex(4)}@example.test", password: "synthetic-password-123", admin: false, confirmation_role: "supervisor")

    expect(build(agents: [ stranger ])).not_to be_valid
    expect(build(agents: [ supervisor ])).not_to be_valid
  end

  it "keeps the delay between 5 minutes and a day, the amounts positive and the range in order" do
    expect(build(timeout_minutes: 30)).to be_valid
    expect(build(timeout_minutes: 4)).not_to be_valid
    expect(build(timeout_minutes: 1441)).not_to be_valid
    expect(build(timeout_minutes: 5)).to be_valid
    expect(build(min_amount_cents: -1)).not_to be_valid
    expect(build(min_amount_cents: 10_000, max_amount_cents: 5_000)).not_to be_valid
    expect(build(min_amount_cents: 5_000, max_amount_cents: 5_000)).to be_valid
    expect(build(distribution: "random")).not_to be_valid
  end

  describe "#matches?" do
    let(:order) { Struct.new(:total_cents).new(20_000) }

    it "tests the amount range, edges included" do
      expect(build(min_amount_cents: 20_000).matches?(order, source_key: "manual")).to be(true)
      expect(build(min_amount_cents: 20_001).matches?(order, source_key: "manual")).to be(false)
      expect(build(max_amount_cents: 20_000).matches?(order, source_key: "manual")).to be(true)
      expect(build(max_amount_cents: 19_999).matches?(order, source_key: "manual")).to be(false)
      expect(build.matches?(order, source_key: "manual")).to be(true)                       # no condition: every order
    end

    it "tests the sources: every source when none is chosen, else only the chosen ones" do
      rule = build(sources: [ "manual", "12", "" ])

      expect(rule.valid?).to be(true)
      expect(rule.sources).to eq(%w[manual 12])                                              # blanks dropped
      expect(rule.matches?(order, source_key: "manual")).to be(true)
      expect(rule.matches?(order, source_key: 12)).to be(true)
      expect(rule.matches?(order, source_key: "99")).to be(false)
      expect(build(sources: []).all_sources?).to be(true)
    end
  end

  describe "#weights" do
    it "is 1 each when equal and the percentage of each agent when by percentage" do
      expect(build.weights).to eq(saida.id => 1, omar.id => 1)
      expect(build(percents: [ 70, 30 ]).weights).to eq(saida.id => 70, omar.id => 30)
    end
  end
end
