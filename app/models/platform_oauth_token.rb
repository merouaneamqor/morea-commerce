# frozen_string_literal: true

require "digest"

class PlatformOauthToken < ApplicationRecord
  belongs_to :user

  ACCESS_TTL = 1.hour
  REFRESH_TTL = 90.days
  ACCESS_PREFIX = "morea_platform_oa_"
  REFRESH_PREFIX = "morea_platform_or_"

  validates :token_digest, :refresh_digest, :client_id, :resource, :expires_at, :refresh_expires_at, presence: true

  def self.issue!(user:, client_id:, resource:)
    user.with_lock do
      raise ArgumentError, "Active superadmin required" unless user.active? && user.super_admin?

      access = "#{ACCESS_PREFIX}#{SecureRandom.urlsafe_base64(32)}"
      refresh = "#{REFRESH_PREFIX}#{SecureRandom.urlsafe_base64(32)}"
      create!(user: user, client_id: client_id, resource: resource,
        token_digest: digest(access), refresh_digest: digest(refresh),
        expires_at: ACCESS_TTL.from_now, refresh_expires_at: REFRESH_TTL.from_now)
      [ access, refresh ]
    end
  end

  def self.authenticate(secret)
    return unless valid_secret?(secret, ACCESS_PREFIX)

    grant = includes(:user).find_by(token_digest: digest(secret), revoked_at: nil)
    grant if grant && grant.expires_at > Time.current && grant.user.active? && grant.user.super_admin?
  end

  def self.rotate!(refresh_token, client_id:, resource: nil)
    return unless valid_secret?(refresh_token, REFRESH_PREFIX) && client_id.present?

    transaction do
      grant = find_by(refresh_digest: digest(refresh_token))
      next unless grant

      user = grant.user
      next unless user

      user.with_lock do
        grant.lock!
        next unless grant.revoked_at.nil? && grant.refresh_expires_at > Time.current && grant.client_id == client_id
        next if !resource.nil? && resource != grant.resource
        next unless user.active? && user.super_admin?

        pair = issue!(user: user, client_id: grant.client_id, resource: grant.resource)
        grant.update!(revoked_at: Time.current)
        pair
      end
    end
  rescue ActiveRecord::RecordNotFound
    nil
  end

  def self.digest(secret)
    Digest::SHA256.hexdigest(secret)
  end

  def self.valid_secret?(secret, prefix)
    secret.is_a?(String) && secret.start_with?(prefix) && secret.bytesize <= 256
  end
end
