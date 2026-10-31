# frozen_string_literal: true

require "rails_helper"

RSpec.describe PlatformApiToken, type: :model do
  let!(:owner) { User.create!(email: "platform-token-#{SecureRandom.hex(4)}@example.test", password: "synthetic-credential-123", admin: true, super_admin: true) }

  it "stores only a digest and binds authentication to an active superadmin" do
    secret = described_class.issue!(user: owner)
    grant = described_class.authenticate(secret)
    expect(grant.user).to eq(owner)
    expect(grant.token_digest).not_to eq(secret)
    expect(grant.last_four).to eq(secret.last(4))
    expect(grant.expires_at).to be_within(5.seconds).of(90.days.from_now)
    owner.update!(status: "suspended")
    expect(described_class.authenticate(secret)).to be_nil
    owner.update!(status: "archived")
    expect(described_class.authenticate(secret)).to be_nil
    owner.update!(status: "active")
    owner.update_columns(super_admin: false)
    expect(described_class.authenticate(secret)).to be_nil
  end

  it "rotates, revokes and expires credentials" do
    old_secret = described_class.issue!(user: owner)
    secret = described_class.issue!(user: owner)
    expect(described_class.authenticate(old_secret)).to be_nil
    grant = described_class.authenticate(secret)
    # Keep subsecond precision: travel_to otherwise rounds down before expiry.
    travel_to(grant.expires_at - Rational(1, 1_000_000), with_usec: true) do
      expect(described_class.authenticate(secret)).to eq(grant)
    end
    travel_to(grant.expires_at, with_usec: true) { expect(described_class.authenticate(secret)).to be_nil }
    travel_to(grant.expires_at + Rational(1, 1_000_000), with_usec: true) { expect(described_class.authenticate(secret)).to be_nil }
    grant.update!(revoked_at: Time.current)
    expect(described_class.authenticate(secret)).to be_nil
  end

  it "refuses issuance to inactive users and invalid tokens" do
    owner.update!(status: "suspended")
    expect { described_class.issue!(user: owner) }.to raise_error(ArgumentError)
    [ nil, "", "merchant-token", "morea_platform_wrong", "morea_platform_#{'a' * 300}" ].each do |secret|
      expect(described_class.authenticate(secret)).to be_nil
    end
  end
end
