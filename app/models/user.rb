class User < ApplicationRecord
  has_secure_password

  belongs_to :store

  validates :email, presence: true, uniqueness: { scope: :store_id }
  normalizes :email, with: ->(e) { e.strip.downcase }
end
