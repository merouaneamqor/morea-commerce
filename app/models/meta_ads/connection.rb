# frozen_string_literal: true

module MetaAds
  # One Meta authorization per store. Reconnecting updates this row instead of creating another.
  class Connection < ApplicationRecord
    STATUSES = %w[active needs_reauthorization disconnected].freeze

    belongs_to :store
    has_many :ad_accounts, class_name: "MetaAds::AdAccount", dependent: :restrict_with_error
    attr_readonly :store_id

    validates :status, inclusion: { in: STATUSES }
    validates :store_id, uniqueness: true
    validates :access_token_ciphertext, presence: true, if: :active?

    # Authenticated encryption keyed off secret_key_base, like StoreConnection.
    # Rotating that key requires merchants to reconnect.
    def access_token
      return if access_token_ciphertext.blank?

      encryptor.decrypt_and_verify(access_token_ciphertext, purpose: "meta-ads-access-token")
    end

    def access_token=(value)
      self.access_token_ciphertext = value.present? ? encryptor.encrypt_and_sign(value.to_s, purpose: "meta-ads-access-token") : nil
    end

    def active?
      status == "active"
    end

    def token_expired?
      token_expires_at.present? && token_expires_at <= Time.current
    end

    # Tokens are removed; synced history stays until a merchant explicitly deletes it.
    def disconnect!
      with_lock do
        update!(status: "disconnected", access_token: nil, token_expires_at: nil, oauth_state_digest: nil, oauth_state_expires_at: nil)
        ad_accounts.update_all(selected: false, sync_status: "pending", next_sync_at: nil)
      end
    end

    # Auth or permission failure: stop syncing, keep history, ask the merchant to reconnect.
    def mark_needs_reauthorization!(code)
      with_lock do
        update!(status: "needs_reauthorization", last_error_code: code, access_token: nil)
        ad_accounts.where(selected: true).update_all(sync_status: "needs_reauthorization", next_sync_at: nil)
      end
    end

    # Never expose credentials through inspect, logs or serialization.
    def inspect
      "#<#{self.class.name} id=#{id} store_id=#{store_id} status=#{status}>"
    end

    def serializable_hash(options = nil)
      super((options || {}).merge(except: %w[access_token_ciphertext oauth_state_digest]))
    end

    private

    def encryptor
      key = Rails.application.key_generator.generate_key("morea-meta-ads-connection-v1", 32)
      ActiveSupport::MessageEncryptor.new(key, cipher: "aes-256-gcm", serializer: JSON)
    end
  end
end
