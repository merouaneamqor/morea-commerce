# frozen_string_literal: true

require "rails_helper"

RSpec.describe Platform::DeadJobCleanup do
  describe ".orphan_class?" do
    it "treats missing constants and mailer-style names as orphans" do
      expect(described_class.orphan_class?("RebuildBusinessSearchIndexJob")).to eq(true)
      expect(described_class.orphan_class?("BookingMailer#confirmation_otp_for_customer")).to eq(true)
      expect(described_class.orphan_class?("RegistrationMailer#verification")).to eq(false)
      expect(described_class.orphan_class?("SenditCitiesRefreshJob")).to eq(false)
    end
  end

  describe ".clear_runtime_orphans!" do
    it "removes missing-class jobs from retry, schedule, and dead sets" do
      orphan = double("orphan-job", display_class: "RebuildBusinessSearchIndexJob")
      keep = double("keep-job", display_class: "SenditCitiesRefreshJob")
      allow(orphan).to receive(:delete)
      allow(keep).to receive(:delete)

      retry_set = double("retry-set")
      scheduled_set = double("scheduled-set")
      dead_set = double("dead-set")

      allow(retry_set).to receive(:each).and_yield(orphan).and_yield(keep)
      allow(scheduled_set).to receive(:each)
      allow(dead_set).to receive(:each)

      stub_const("Sidekiq::RetrySet", Class.new)
      stub_const("Sidekiq::ScheduledSet", Class.new)
      stub_const("Sidekiq::DeadSet", Class.new)
      allow(Sidekiq::RetrySet).to receive(:new).and_return(retry_set)
      allow(Sidekiq::ScheduledSet).to receive(:new).and_return(scheduled_set)
      allow(Sidekiq::DeadSet).to receive(:new).and_return(dead_set)

      result = described_class.clear_runtime_orphans!

      expect(result.removed).to eq(1)
      expect(result.mode).to eq("runtime_orphans")
      expect(orphan).to have_received(:delete)
      expect(keep).not_to have_received(:delete)
    end
  end
end
