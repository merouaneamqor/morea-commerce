# frozen_string_literal: true

require "rails_helper"

RSpec.describe User, "password policy" do
  let(:store) { Store.create!(slug: "pw-#{SecureRandom.hex(5)}", name: "Synthetic password workspace", currency: "MAD") }

  def build(password, email: "staff-#{SecureRandom.hex(4)}@example.test")
    store.users.new(name: "Synthetic", email: email, password: password, admin: true)
  end

  it "requires 12 characters on every flow, not only recovery" do
    expect(build("a" * 11)).not_to be_valid
    expect(build("a1b2c3d4e5f6")).to be_valid
  end

  it "refuses passwords longer than bcrypt reads" do
    user = build("a" * 73)
    expect(user).not_to be_valid
    expect(user.errors.details[:password].pluck(:error)).to include(:too_long)
  end

  it "refuses a password built from the account's own email name" do
    user = build("anastasia-2027!", email: "anastasia@example.test")
    expect(user).not_to be_valid
    expect(user.errors.details[:password].pluck(:error)).to include(:contains_email)
  end

  it "applies when an existing user changes their password" do
    user = build("synthetic-password-123").tap(&:save!)

    expect(user.update(password: "short")).to be(false)
    expect(user.update(password: "another-synthetic-pass-9", password_confirmation: "another-synthetic-pass-9")).to be(true)
  end

  it "does not lock out or invalidate an existing weaker password until it is changed" do
    user = build("synthetic-password-123").tap(&:save!)
    user.update_columns(password_digest: BCrypt::Password.create("legacy", cost: 4))
    user = described_class.find(user.id)

    expect(user.update(name: "Renamed")).to be(true)
    expect(user.authenticate("legacy")).to be_truthy
  end

  it "renders the email rule in every language" do
    %i[en fr ar].each do |locale|
      expect(I18n.t("activerecord.errors.models.user.attributes.password.contains_email", locale: locale)).not_to include("translation missing")
    end
  end
end
