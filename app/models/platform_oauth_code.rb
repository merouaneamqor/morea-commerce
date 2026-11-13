# frozen_string_literal: true

require "digest"
require "base64"

class PlatformOauthCode < ApplicationRecord
  belongs_to :user

  TTL = 10.minutes
  PREFIX = "morea_platform_oc_"

  validates :code_digest, :client_id, :redirect_uri, :code_challenge, :resource, :expires_at, presence: true
  validates :code_challenge, format: { with: /\A[A-Za-z0-9_-]{43}\z/ }

  def self.issue!(user:, client_id:, redirect_uri:, code_challenge:, resource:)
    user.with_lock do
      raise ArgumentError, "Active superadmin required" unless user.active? && user.super_admin?

      code = "#{PREFIX}#{SecureRandom.urlsafe_base64(32)}"
      create!(user: user, code_digest: PlatformOauthToken.digest(code), client_id: client_id,
        redirect_uri: redirect_uri, code_challenge: code_challenge, resource: resource, expires_at: TTL.from_now)
      code
    end
  end

  def self.exchange!(code:, client_id:, redirect_uri:, code_verifier:, resource: nil)
    return unless PlatformOauthToken.valid_secret?(code, PREFIX)

    transaction do
      grant = find_by(code_digest: PlatformOauthToken.digest(code))
      next unless grant

      user = grant.user
      next unless user

      user.with_lock do
        grant.lock!
        next unless grant.consumed_at.nil? && grant.expires_at > Time.current
        next unless grant.client_id == client_id && grant.redirect_uri == redirect_uri
        next if !resource.nil? && resource != grant.resource
        next unless valid_verifier?(code_verifier, grant.code_challenge)
        next unless user.active? && user.super_admin?

        pair = PlatformOauthToken.issue!(user: user, client_id: grant.client_id, resource: grant.resource)
        grant.update!(consumed_at: Time.current)
        pair
      end
    end
  rescue ActiveRecord::RecordNotFound
    nil
  end

  def self.valid_verifier?(verifier, challenge)
    return false unless verifier.is_a?(String) && verifier.match?(/\A[A-Za-z0-9._~-]{43,128}\z/)

    expected = Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)
    ActiveSupport::SecurityUtils.secure_compare(expected, challenge)
  end
end
