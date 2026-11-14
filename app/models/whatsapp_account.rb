# One WhatsApp Business (Cloud API) number of a store. The access token is stored encrypted (keyed off secret_key_base, like the other connections)
# and is never shown again, only its last characters.
class WhatsappAccount < ApplicationRecord
  belongs_to :store
  has_many :messages, class_name: "WhatsappMessage", dependent: :destroy

  scope :active, -> { where(active: true) }
  scope :auto, -> { active.where(auto_send_new_orders: true) }

  validates :name, presence: true, length: { maximum: 80 }
  validates :phone_number_id, presence: true, format: { with: /\A\d{5,30}\z/, message: "must be the numeric Phone Number ID from Meta" }, uniqueness: { scope: :store_id }
  validates :business_account_id, format: { with: /\A\d{5,30}\z/ }, allow_blank: true
  validates :api_version, format: { with: /\Av\d{1,2}\.\d{1,2}\z/ }
  validates :display_phone, length: { maximum: 40 }
  validates :access_token_ciphertext, presence: true
  validates :new_order_message, length: { maximum: 1000 }
  validate :message_uses_known_keywords

  def access_token
    return if access_token_ciphertext.blank?

    encryptor.decrypt_and_verify(access_token_ciphertext, purpose: "whatsapp-access-token")
  end

  def access_token=(value)
    self.access_token_ciphertext = value.present? ? encryptor.encrypt_and_sign(value.to_s.strip, purpose: "whatsapp-access-token") : nil
  end

  # "••••1234": enough to recognise the token, never the token.
  def token_hint
    token = access_token.to_s
    token.length > 4 ? "••••#{token.last(4)}" : "••••"
  end

  # The text sent to a customer when an order arrives: the merchant's, or the default one.
  def message_template = new_order_message.presence || Whatsapp::Keywords::DEFAULT_MESSAGE

  private

  def message_uses_known_keywords
    unknown = Whatsapp::Keywords.unknown_in(new_order_message.to_s)
    errors.add(:new_order_message, "uses unknown keywords: #{unknown.map { |key| "{{#{key}}}" }.join(", ")}") if unknown.any?
  end

  def encryptor
    key = Rails.application.key_generator.generate_key("morea-whatsapp-account-v1", 32)
    ActiveSupport::MessageEncryptor.new(key, cipher: "aes-256-gcm", serializer: JSON)
  end
end
