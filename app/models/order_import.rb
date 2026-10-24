# frozen_string_literal: true

# Connector identity only: customer payloads and credentials are not retained here.
class OrderImport < ApplicationRecord
  belongs_to :store
  belongs_to :order

  validates :source, presence: true, length: { maximum: 64 },
    format: { with: /\A[a-z0-9][a-z0-9_-]*\z/ }
  validates :external_id, presence: true, length: { maximum: 255 },
    uniqueness: { scope: [ :store_id, :source ] }
  validate :order_belongs_to_store

  private

  def order_belongs_to_store
    errors.add(:order, "must belong to this store") if order && order.store_id != store_id
  end
end
