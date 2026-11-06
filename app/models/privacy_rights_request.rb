# frozen_string_literal: true

class PrivacyRightsRequest < ApplicationRecord
  TYPES = %w[access rectify object delete unsubscribe].freeze
  STATUSES = %w[open in_progress resolved rejected].freeze

  belongs_to :store

  validates :request_type, inclusion: { in: TYPES }
  validates :status, inclusion: { in: STATUSES }
  validates :requester_name, :requester_contact, presence: true
  validates :requester_name, length: { maximum: 120 }
  validates :requester_contact, length: { maximum: 200 }
  validates :details, length: { maximum: 2_000 }, allow_blank: true
  validates :order_number, length: { maximum: 64 }, allow_blank: true

  scope :open_queue, -> { where(status: %w[open in_progress]).order(created_at: :asc) }

  def resolve!
    update!(status: "resolved", resolved_at: Time.current)
  end
end
