class Customer < ApplicationRecord
  belongs_to :store
  has_many :addresses, dependent: :destroy
  has_many :orders, dependent: :restrict_with_exception

  validates :name, :phone, presence: true
  validates :phone, uniqueness: { scope: :store_id }

  normalizes :phone, with: ->(p) { p.to_s.gsub(/[^\d+]/, "") }

  def self.find_or_create_from_checkout!(store:, name:, phone:, city:, address:, district: nil)
    customer = store.customers.find_or_initialize_by(phone: phone.to_s.gsub(/[^\d+]/, ""))
    customer.name = name
    customer.city = city
    customer.save!

    customer.addresses.where(default: true).update_all(default: false)
    customer.addresses.create!(city: city, line1: address, line2: district.presence, default: true)
    customer
  end
end
