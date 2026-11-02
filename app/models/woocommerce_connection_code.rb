class WoocommerceConnectionCode < ApplicationRecord
  belongs_to :store
  belongs_to :user

  def self.authorized?(store:, user:)
    user.active? && (user.super_admin? || (user.admin? && user.store_id == store.id))
  end

  # The one-time code is returned once and only its digest is stored. The PKCE
  # challenge binds redemption to the plugin instance that started the request.
  def self.issue!(store:, user:, site:, code_challenge:)
    raise ActiveRecord::RecordNotFound unless authorized?(store: store, user: user)

    code = SecureRandom.hex(24)
    store.with_lock do
      where(store: store, user: user, consumed_at: nil).update_all(consumed_at: Time.current)
      create!(store: store, user: user, digest: Digest::SHA256.hexdigest(code), expires_at: 10.minutes.from_now,
        site_domain: site, code_challenge: code_challenge)
    end
    code
  end
end
