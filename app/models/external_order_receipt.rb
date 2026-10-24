# frozen_string_literal: true

class ExternalOrderReceipt < ApplicationRecord
  belongs_to :store_connection
  belongs_to :order, optional: true
  validates :external_id, presence: true, length: { maximum: 255 }
  validates :status, inclusion: { in: %w[accepted rejected] }
  validate :same_store

  private

  def same_store
    errors.add(:order, "must belong to the connection's store") if order && order.store_id != store_connection.store_id
  end
end
