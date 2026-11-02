# frozen_string_literal: true

require "digest"

# Platform credentials are deliberately separate from merchant API/OAuth grants.
class PlatformApiToken < ApplicationRecord
  belongs_to :user

  TTL = 90.days
  PREFIX = "morea_platform_"

  validates :token_digest, presence: true, uniqueness: true
  validates :last_four, :expires_at, presence: true

  def self.issue!(user:)
    user.with_lock do
      raise ArgumentError, "Active super admin required" unless user.active? && user.super_admin?

      where(user: user, revoked_at: nil).update_all(revoked_at: Time.current)
      secret = "#{PREFIX}#{SecureRandom.urlsafe_base64(32)}"
      create!(user: user, token_digest: Digest::SHA256.hexdigest(secret), last_four: secret.last(4), expires_at: TTL.from_now)
      secret
    end
  end

  def self.authenticate(secret)
    return unless secret.is_a?(String) && secret.start_with?(PREFIX) && secret.bytesize <= 256

    grant = includes(:user).find_by(token_digest: Digest::SHA256.hexdigest(secret), revoked_at: nil)
    return unless grant && grant.expires_at > Time.current && grant.user.active? && grant.user.super_admin?

    grant
  end
end
