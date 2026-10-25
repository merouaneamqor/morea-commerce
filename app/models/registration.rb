# frozen_string_literal: true

# A self-service owner stays outside the merchant session until they prove email ownership.
class Registration < ApplicationRecord
  has_secure_password validations: false

  belongs_to :user, optional: true

  normalizes :email, with: ->(value) { value.to_s.strip.downcase }
  normalizes :business_name, with: ->(value) { value.to_s.squish }

  validates :business_name, presence: true, length: { in: 2..80 }
  validates :email, presence: true, length: { maximum: 160 }, format: { with: URI::MailTo::EMAIL_REGEXP }, uniqueness: true
  validates :locale, inclusion: { in: Morea::Locales::AVAILABLE.map(&:to_s) }
  # Credentials are chosen only after the visitor proves ownership of the email link.
  validates :password, length: { minimum: 12 }, on: :confirmation
  validates :password_confirmation, presence: true, on: :confirmation
  validates_confirmation_of :password, on: :confirmation
  validate :password_byte_length, on: :confirmation

  before_validation :assign_verification_nonce, on: :create

  generates_token_for :email_verification, expires_in: 24.hours do
    verification_nonce
  end

  def verified?
    verified_at.present?
  end

  def verification_token
    generate_token_for(:email_verification)
  end

  # A resend invalidates all earlier links; rate-limit by email as well as request IP.
  def resend_verification!
    with_lock do
      return false if verified? || verification_sent_at.present? && verification_sent_at > 2.minutes.ago

      update!(verification_nonce: SecureRandom.hex(24), verification_sent_at: Time.current)
    end
    true
  end

  private

  def password_byte_length
    errors.add(:password, :too_long, count: 72) if password.to_s.bytesize > 72
  end

  def assign_verification_nonce
    self.verification_nonce ||= SecureRandom.hex(24)
  end
end
