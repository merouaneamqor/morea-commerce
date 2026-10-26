# frozen_string_literal: true

class StoreConnection < ApplicationRecord
  PROVIDERS = %w[shopify woocommerce youcan].freeze
  SHOPIFY_API_ERRORS = %w[config_missing credentials_missing disconnected invalid_credentials shop_not_permitted missing_scopes source_mismatch rate_limited unavailable invalid_response].freeze

  belongs_to :store
  has_many :external_order_receipts, dependent: :restrict_with_error
  attr_readonly :store_id, :provider, :external_domain, :external_store_id, :token

  before_validation :normalize_identity, if: :new_record?
  validates :provider, inclusion: { in: PROVIDERS }
  validates :name, :external_domain, :token, presence: true
  validates :webhook_secret, presence: true, unless: :shopify_api_configured?
  validates :name, length: { maximum: 100 }
  validates :webhook_secret, length: { minimum: 16, maximum: 1024 }, allow_nil: true
  validates :shopify_api_error_code, inclusion: { in: SHOPIFY_API_ERRORS }, allow_nil: true
  validate :shopify_oauth_provider
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

  %i[shopify_access_token shopify_refresh_token].each do |attribute|
    define_method(attribute) do
      ciphertext = public_send("#{attribute}_ciphertext")
      secret_encryptor.decrypt_and_verify(ciphertext, purpose: "store-connection-#{attribute}") if ciphertext.present?
    end

    define_method("#{attribute}=") do |value|
      public_send("#{attribute}_ciphertext=", value.present? ? secret_encryptor.encrypt_and_sign(value.to_s, purpose: "store-connection-#{attribute}") : nil)
    end
  end

  def shopify_api_configured?
    provider == "shopify" && shopify_oauth?
  end

  def shopify_api_connected?
    active? && shopify_api_configured? && shopify_api_verified_at.present? && shopify_api_error_code.nil? &&
      ((shopify_access_token_ciphertext.present? && shopify_access_token_expires_at&.future?) ||
        (shopify_refresh_token_ciphertext.present? && shopify_refresh_token_expires_at&.future?))
  end

  def connection_state
    return "disconnected" unless active?
    return shopify_api_connected? ? "verified" : "configured" if shopify_oauth?

    verified_at? ? "verified" : "configured"
  end

  private

  def shopify_oauth_provider
    if provider != "shopify" && shopify_oauth?
      errors.add(:provider, "must be Shopify for API authorization")
    end
  end

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
