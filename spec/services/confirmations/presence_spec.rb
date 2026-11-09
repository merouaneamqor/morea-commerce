require "rails_helper"

RSpec.describe Confirmations::Presence do
  include ActiveSupport::Testing::TimeHelpers
  after { travel_back }
  let(:password) { "synthetic-password-123" }
  let(:store) { Store.create!(slug: "presence-#{SecureRandom.hex(5)}", name: "Synthetic desk", currency: "MAD") }
  let(:agent) { store.users.create!(name: "Saida", email: "agent-#{SecureRandom.hex(5)}@example.test", password: password, confirmation_role: "agent") }

  def presence_for(user, workspace: store)
    described_class.new(store: workspace, user: user)
  end

  it "opens a session while the pages are open and keeps a second ping on the same session" do
    presence_for(agent).ping!

    expect(ConfirmationShift.open.where(store: store, user: agent).count).to eq(1)
    expect { presence_for(agent).ping! }.not_to change { ConfirmationShift.where(store: store, user: agent).count }
    expect(presence_for(agent).present?).to be(true)
  end

  it "closes the session when the agent leaves, and stops the stat at the last open page" do
    presence_for(agent).ping!
    travel 2.minutes
    presence_for(agent).leave!

    shift = ConfirmationShift.where(store: store, user: agent).sole
    expect(shift.ended_at).to be_present
    expect(presence_for(agent).present?).to be(false)
    expect(presence_for(agent).seconds_within(10.minutes.ago..Time.current)).to be_between(119, 121)
  end

  it "starts a new session after the pages have been closed longer than the grace window" do
    presence_for(agent).ping!
    travel ConfirmationShift::PRESENCE_GRACE + 5.seconds
    presence_for(agent).ping!

    shifts = ConfirmationShift.where(store: store, user: agent).order(:started_at)
    expect(shifts.size).to eq(2)
    expect(shifts.first.ended_at).to be_present
    expect(shifts.second.ended_at).to be_nil
  end

  it "denies a store admin and staff from another workspace" do
    manager = store.users.create!(email: "manager-#{SecureRandom.hex(5)}@example.test", password: password, admin: true)
    foreign = Store.create!(slug: "foreign-#{SecureRandom.hex(5)}", name: "Other", currency: "MAD")
    outsider = foreign.users.create!(email: "outsider-#{SecureRandom.hex(5)}@example.test", password: password, confirmation_role: "agent")

    expect { presence_for(manager).ping! }.to raise_error(described_class::Error, "Confirmation agent access required.")
    expect { presence_for(outsider).ping! }.to raise_error(described_class::Error, "Confirmation agent access required.")
    expect(ConfirmationShift.where(store: store).count).to eq(0)
  end

  it "keeps the page-open history after the account is deleted" do
    presence_for(agent).ping!
    presence_for(agent).leave!
    label = agent.name.presence || agent.email

    agent.destroy!

    shift = ConfirmationShift.where(store: store).sole
    expect(shift.user_id).to be_nil
    expect(shift.actor_label).to eq(label)
  end

  it "records pages open without changing pay, which stays per delivered order" do
    agent.update!(pay_per_delivery_cents: 800)
    presence_for(agent).ping!
    travel 20.seconds
    presence_for(agent).ping!

    summary = Team::AgentEarnings.new(store: store, range: Time.current.all_day).summary_for(agent)

    expect(presence_for(agent).seconds_within(Time.current.all_day)).to be_between(19, 21)
    expect(summary.earned_period).to eq(0)
    expect(summary.figures.delivered).to eq(0)
  end
end
