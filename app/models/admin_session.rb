# frozen_string_literal: true

# Server-side admin session: the cookie holds only a random token, so a session can expire or be revoked.
class AdminSession < ApplicationRecord
  IDLE_TIMEOUT = 12.hours
  ABSOLUTE_LIFETIME = 30.days
  TOUCH_INTERVAL = 1.minute

  belongs_to :user
  belongs_to :store, optional: true

  scope :active, -> { where(revoked_at: nil).where("expires_at > ?", Time.current).where("last_seen_at > ?", IDLE_TIMEOUT.ago) }

  def self.digest(token) = Digest::SHA256.hexdigest(token.to_s)

  # Returns [record, plaintext_token]; only the digest is stored.
  def self.start!(user:, store:, ip: nil, user_agent: nil)
    token = SecureRandom.urlsafe_base64(32)
    now = Time.current
    record = create!(user: user, store: store, token_digest: digest(token), last_seen_at: now,
      expires_at: now + ABSOLUTE_LIFETIME, ip: ip, user_agent: user_agent.to_s.first(255))
    [ record, token ]
  end

  def self.find_active(token)
    return if token.blank?

    session = active.find_by(token_digest: digest(token))
    session&.touch_seen!
    session
  end

  def self.revoke_all_for(user, except: nil)
    scope = where(user_id: user.id, revoked_at: nil)
    scope = scope.where.not(id: except.id) if except
    scope.update_all(revoked_at: Time.current, updated_at: Time.current)
  end

  def revoke!
    update!(revoked_at: Time.current) unless revoked_at
  end

  def touch_seen!
    update_columns(last_seen_at: Time.current) if last_seen_at < TOUCH_INTERVAL.ago
  end
end
