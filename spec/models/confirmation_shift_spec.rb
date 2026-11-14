# frozen_string_literal: true

require "rails_helper"

RSpec.describe ConfirmationShift do
  include ActiveSupport::Testing::TimeHelpers

  let(:store) { Store.create!(slug: "shift-#{SecureRandom.hex(4)}", name: "Shift", currency: "MAD") }
  let(:agent) do
    store.users.create!(name: "Saida", email: "agent-#{SecureRandom.hex(4)}@example.test",
      password: "synthetic-password-123", confirmation_role: "agent")
  end

  it "captures the actor label and requires a desk worker of this store" do
    shift = described_class.create!(store: store, user: agent, started_at: Time.current, last_seen_at: Time.current)
    expect(shift.actor_label).to eq("Saida")

    foreign = Store.create!(slug: "shift-fx-#{SecureRandom.hex(4)}", name: "Other", currency: "MAD")
    outsider = foreign.users.create!(name: "Out", email: "out-#{SecureRandom.hex(4)}@example.test",
      password: "synthetic-password-123", confirmation_role: "agent")

    bad = described_class.new(store: store, user: outsider, started_at: Time.current, last_seen_at: Time.current)
    expect(bad).not_to be_valid
    expect(bad.errors[:user]).to be_present
  end

  it "treats presence as fresh only inside the grace window" do
    travel_to(Time.zone.local(2026, 11, 5, 12, 0, 0)) do
      shift = described_class.create!(store: store, user: agent, started_at: Time.current, last_seen_at: Time.current)
      expect(shift.fresh?).to be(true)

      travel ConfirmationShift::PRESENCE_GRACE
      expect(shift.fresh?).to be(true)

      travel 1.second
      expect(shift.fresh?(now: Time.current)).to be(false)
    end
  end

  it "counts open seconds until now when fresh, and until last_seen when stale" do
    travel_to(Time.zone.local(2026, 11, 5, 12, 0, 0)) do
      shift = described_class.create!(
        store: store, user: agent, started_at: 2.minutes.ago, last_seen_at: Time.current
      )
      range = 10.minutes.ago..10.minutes.from_now
      expect(shift.seconds_within(range)).to be_between(119, 121)

      travel ConfirmationShift::PRESENCE_GRACE + 5.seconds
      expect(shift.seconds_within(range, now: Time.current)).to be_between(119, 121)
    end
  end

  it "finds overlapping open and closed shifts in a range" do
    early = described_class.create!(store: store, user: agent, started_at: 2.hours.ago,
      last_seen_at: 90.minutes.ago, ended_at: 1.hour.ago)
    open_shift = described_class.create!(store: store, user: agent, started_at: 30.minutes.ago,
      last_seen_at: Time.current)

    range = 45.minutes.ago..Time.current
    expect(described_class.overlapping(range)).to contain_exactly(open_shift)
    expect(described_class.overlapping(3.hours.ago..Time.current)).to include(early, open_shift)
  end
end
