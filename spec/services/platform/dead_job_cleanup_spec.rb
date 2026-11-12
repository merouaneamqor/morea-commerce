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
end
