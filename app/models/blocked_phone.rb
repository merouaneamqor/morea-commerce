# A phone number a store blocked. A new order from it does not enter the confirmation queue: it lands in the
# "Bloqués" tab. Agents can block (a reason is required); only owners and managers can unblock.
class BlockedPhone < ApplicationRecord
  belongs_to :store
  belongs_to :blocked_by, class_name: "User", optional: true

  validates :phone_key, presence: true, uniqueness: { scope: :store_id }
  validates :reason, presence: true, length: { maximum: 500 }

  before_validation { self.reason = reason.to_s.strip }

  # "0612 34 56 78", "+212612345678" and "00212612345678" are the same number: the last 9 digits.
  def self.key_for(phone)
    digits = phone.to_s.gsub(/\D/, "")
    digits.length >= 9 ? digits.last(9) : digits
  end

  def self.blocked?(store, *phones)
    keys = phones.map { |phone| key_for(phone) }.reject(&:blank?)
    keys.any? && where(store: store, phone_key: keys).exists?
  end

  def self.block!(store:, phone:, reason:, user:)
    find_or_initialize_by(store: store, phone_key: key_for(phone)).tap do |entry|
      entry.reason = reason if entry.new_record?
      entry.blocked_by ||= user
      entry.save!
    end
  end
end
