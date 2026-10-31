class SealloConnectionCode < ApplicationRecord
  belongs_to :store
  belongs_to :user

  def self.issue!(store:, user:)
    raise ActiveRecord::RecordNotFound unless user.active? && (user.super_admin? || (user.admin? && user.store_id == store.id))

    code = SecureRandom.hex(24)
    store.with_lock do
      where(store: store, user: user, consumed_at: nil).update_all(consumed_at: Time.current)
      create!(store: store, user: user, digest: Digest::SHA256.hexdigest(code), expires_at: 10.minutes.from_now)
    end
    code
  end
end
