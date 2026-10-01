class Discount < ApplicationRecord
  belongs_to :store

  validates :code, :discount_type, :value, presence: true
  validates :code, uniqueness: { scope: :store_id }
end
