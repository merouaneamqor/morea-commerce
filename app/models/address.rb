class Address < ApplicationRecord
  belongs_to :customer

  validates :city, :line1, presence: true
end
