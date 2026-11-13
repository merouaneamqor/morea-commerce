class AgentPayment < ApplicationRecord
  METHODS = %w[cash bank_transfer].freeze
  PROOF_TYPES = %w[image/png image/jpeg image/webp application/pdf].freeze
  PROOF_MAX_BYTES = 5.megabytes

  belongs_to :store
  belongs_to :user
  belongs_to :paid_by, class_name: "User", optional: true

  has_many :agent_deductions, dependent: :nullify
  # The receipt or the bank transfer slip. Required for a bank transfer, optional for cash.
  has_one_attached :proof

  # What was handed over: the earnings settled by this payout minus the deductions it subtracted.
  def cash_cents = amount_cents - deductions_cents

  validates :amount_cents, numericality: { only_integer: true, greater_than: 0 }
  validates :paid_at, presence: true
  validates :payment_method, inclusion: { in: METHODS }, allow_nil: true
  validates :reference, length: { maximum: 200 }
  validate :user_belongs_to_store
  validate :proof_is_a_small_image_or_pdf
  validate :bank_transfer_has_a_proof, on: :create

  private

  def user_belongs_to_store
    errors.add(:user, "must belong to this store") if user && user.store_id != store_id
  end

  def proof_is_a_small_image_or_pdf
    return unless proof.attached?

    errors.add(:proof, "must be a PNG, JPEG, WebP image or a PDF") unless PROOF_TYPES.include?(proof.blob.content_type)
    errors.add(:proof, "must be 5 MB or less") if proof.blob.byte_size > PROOF_MAX_BYTES
  end

  def bank_transfer_has_a_proof
    errors.add(:proof, "is required for a bank transfer") if payment_method == "bank_transfer" && !proof.attached?
  end
end
