# frozen_string_literal: true

class StoreConnection < ApplicationRecord
  PROVIDERS = %w[shopify woocommerce youcan].freeze

  belongs_to :store
  has_many :external_order_receipts, dependent: :restrict_with_error
  attr_readonly :store_id, :provider, :external_domain, :external_store_id, :token

  before_validation :normalize_identity, on: :create
  validates :provider, inclusion: { in: PROVIDERS }
  validates :name, :external_domain, :token, :webhook_secret, presence: true
  validates :name, length: { maximum: 100 }
  validates :webhook_secret, length: { minimum: 16, maximum: 1024 }
  validates :token, uniqueness: true
  validates :external_domain, format: { with: /\A[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?\z/ }, length: { maximum: 253 }
  validates :external_domain, uniqueness: { scope: %i[store_id provider] }
  validates :external_store_id, presence: true, if: -> { provider == "youcan" }
  validates :external_store_id, format: { with: /\A[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\z/i }, allow_blank: true
  validate :shopify_domain

  # Authenticated encryption uses the app's existing stable secret_key_base.
  # Rotating that key requires re-entering provider secrets before intake resumes.
  def webhook_secret
    return if webhook_secret_ciphertext.blank?

    secret_encryptor.decrypt_and_verify(webhook_secret_ciphertext, purpose: "store-connection-webhook")
  end

  def webhook_secret=(value)
    self.webhook_secret_ciphertext = value.present? ? secret_encryptor.encrypt_and_sign(value.to_s, purpose: "store-connection-webhook") : nil
  end

  def connection_state
    return "disconnected" unless active?

    verified_at? ? "verified" : "configured"
  end

  private

  def secret_encryptor
    key = Rails.application.key_generator.generate_key("morea-store-connection-v1", 32)
    ActiveSupport::MessageEncryptor.new(key, cipher: "aes-256-gcm", serializer: JSON)
  end

  def normalize_identity
    self.token ||= SecureRandom.hex(24)
    self.name = name.to_s.strip
    self.external_domain = external_domain.to_s.strip.downcase.delete_suffix(".")
    self.external_store_id = external_store_id.to_s.strip.presence
  end

  def shopify_domain
    if provider == "shopify" && !external_domain.to_s.match?(/\A[a-z0-9][a-z0-9-]*\.myshopify\.com\z/)
      errors.add(:external_domain, "must be the store's myshopify.com domain")
    end
  end
end
