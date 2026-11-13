# A message sent (or that failed to send) through a WhatsappAccount: the automatic message of a new order, or a test.
class WhatsappMessage < ApplicationRecord
  KINDS = %w[new_order test].freeze
  STATUSES = %w[queued sent failed].freeze

  belongs_to :store
  belongs_to :whatsapp_account
  belongs_to :order, optional: true

  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }
  validates :to_phone, :body, presence: true
  validates :order_id, uniqueness: { scope: :kind }, if: -> { kind == "new_order" && order_id.present? }

  scope :recent, -> { order(created_at: :desc, id: :desc) }
end
