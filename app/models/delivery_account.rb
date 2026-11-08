# frozen_string_literal: true

# A merchant's account at a delivery company. API keys are stored encrypted and are never rendered back.
class DeliveryAccount < ApplicationRecord
  ACCOUNT_TYPES = %w[normal premium].freeze
  # Providers whose connector can create parcels automatically.
  SHIPPABLE = %w[sendit ozon ameex].freeze

  belongs_to :store

  validates :provider, inclusion: { in: ->(_) { Carriers.providers.keys } }
  validates :name, presence: true, length: { maximum: 120 }
  validates :code, presence: true, length: { maximum: 12 }, uniqueness: { scope: :store_id }
  validates :account_type, inclusion: { in: ACCOUNT_TYPES }
  validates :contact_name, length: { maximum: 120 }
  validates :contact_phone, length: { maximum: 30 }
  validates :pickup_city, length: { maximum: 120 }
  validates :delivery_fee, :return_fee, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 9999 }, allow_nil: true
  validate :default_must_be_shippable, if: :ships_by_default?

  before_validation :assign_code, on: :create
  before_save :clear_other_defaults, if: -> { ships_by_default? && will_save_change_to_ships_by_default? }

  def provider_info = Carriers.provider(provider)

  def shippable?
    SHIPPABLE.include?(provider) && credentials? && is_active?
  end

  def credentials
    return {} if credentials_ciphertext.blank?

    encryptor.decrypt_and_verify(credentials_ciphertext, purpose: "delivery-account-credentials") || {}
  end

  def credentials=(values)
    values = values.to_h.compact_blank
    self.credentials_ciphertext = values.empty? ? nil : encryptor.encrypt_and_sign(values, purpose: "delivery-account-credentials")
  end

  def credentials?
    credentials_ciphertext.present?
  end

  def sendit?
    provider == "sendit"
  end

  def ozon?
    provider == "ozon"
  end

  def ameex?
    provider == "ameex"
  end

  # URL the merchant pastes in the courier's webhook UI; the token authenticates inbound calls.
  def webhook_url
    return if webhook_token.blank?

    path = case provider
    when "sendit" then "webhooks/sendit/#{store.slug}"
    when "ozon" then "webhooks/ozon/#{store.slug}"
    when "ameex" then "webhooks/ameex/#{store.slug}"
    end
    return unless path

    "#{Store.platform_origin}/#{path}?token=#{webhook_token}"
  end

  def generate_webhook_token
    self.webhook_token ||= SecureRandom.urlsafe_base64(24)
  end

  # The secret key is never shown again in full: only its last characters, to recognise it.
  def secret_hint
    secret = credentials["api_secret"].to_s
    secret.empty? ? nil : "••••••••#{secret.last(4)}"
  end

  private

  # SEN1, SEN2, OZO1...: the first three letters of the company name and a number.
  def assign_code
    return if code.present?

    prefix = provider_info["name"].to_s.gsub(/[^a-z]/i, "").first(3).upcase.presence || "LIV"
    taken = store ? store.delivery_accounts.pluck(:code) : []
    number = 1
    number += 1 while taken.include?("#{prefix}#{number}")
    self.code = "#{prefix}#{number}"
  end

  def default_must_be_shippable
    return if SHIPPABLE.include?(provider) && credentials? && is_active?

    errors.add(:ships_by_default, "only an active connected Sendit, Ozon Express or Ameex account can ship by default")
  end

  def clear_other_defaults
    return unless store

    store.delivery_accounts.where.not(id: id).where(ships_by_default: true).update_all(ships_by_default: false, updated_at: Time.current)
  end

  def encryptor
    key = Rails.application.key_generator.generate_key("morea-delivery-account-v1", 32)
    ActiveSupport::MessageEncryptor.new(key, cipher: "aes-256-gcm", serializer: JSON)
  end
end
