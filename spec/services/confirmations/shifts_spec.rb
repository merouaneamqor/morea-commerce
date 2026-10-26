require "rails_helper"

RSpec.describe Confirmations::Shifts do
  let(:password) { "synthetic-password-123" }
  let(:store) { Store.create!(slug: "shifts-#{SecureRandom.hex(5)}", name: "Synthetic desk", currency: "MAD") }
  let(:agent) { store.users.create!(email: "agent-#{SecureRandom.hex(5)}@example.test", password: password, admin: true) }

  def shifts_for(user, workspace: store)
    described_class.new(store: workspace, user: user)
  end

  it "opens one shift and refuses a second clock-in" do
    shifts_for(agent).clock_in

    expect(ConfirmationShift.open.where(store: store, user: agent).count).to eq(1)
    expect { shifts_for(agent).clock_in }.to raise_error(described_class::Error, "You are already on shift.")
  end

  it "closes the open shift and refuses a clock-out when none is open" do
    shift = shifts_for(agent).clock_in
    shifts_for(agent).clock_out

    expect(shift.reload.ended_at).to be_present
    expect { shifts_for(agent).clock_out }.to raise_error(described_class::Error, "You are not on shift.")
  end

  it "denies staff from another workspace" do
    foreign = Store.create!(slug: "foreign-#{SecureRandom.hex(5)}", name: "Other", currency: "MAD")
    outsider = foreign.users.create!(email: "outsider-#{SecureRandom.hex(5)}@example.test", password: password, admin: true)

    expect { shifts_for(outsider).clock_in }.to raise_error(described_class::Error, "Store administration access required.")
    expect(ConfirmationShift.where(store: store).count).to eq(0)
  end

  it "enforces one open shift per agent in the database" do
    ConfirmationShift.create!(store: store, user: agent, started_at: 1.hour.ago)

    expect {
      ConfirmationShift.create!(store: store, user: agent, started_at: Time.current)
    }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "keeps hours history with an actor label after the account is deleted" do
    shifts_for(agent).clock_in
    shifts_for(agent).clock_out
    label = agent.name.presence || agent.email

    agent.destroy!

    shift = ConfirmationShift.where(store: store).sole
    expect(shift.user_id).to be_nil
    expect(shift.actor_label).to eq(label)
  end
end
