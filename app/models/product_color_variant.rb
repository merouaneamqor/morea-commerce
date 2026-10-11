# frozen_string_literal: true

class ProductColorVariant < ApplicationRecord
  PRESET_COLORS = {
    "baby_pink" => "#F4C2C2",
    "black" => "#1A1A1A",
    "taupe" => "#8B7D6B",
    "ocean_blue" => "#006994"
  }.freeze

  STATUSES = %w[pending processing ready failed].freeze

  belongs_to :product
  belongs_to :product_variant, optional: true

  has_one_attached :result_image
  has_one_attached :mask_image

  validates :hex_color, presence: true, format: { with: /\A#?[0-9A-Fa-f]{3,8}\z/ }
  validates :source_attachment_id, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :newest_first, -> { order(created_at: :desc) }

  def processing!
    update!(status: "processing", error_message: nil)
  end

  def mark_ready!
    update!(status: "ready", error_message: nil)
  end

  def mark_failed!(message)
    update!(status: "failed", error_message: message.to_s.truncate(500))
  end

  def normalized_hex
    hex = hex_color.to_s.strip
    hex.start_with?("#") ? hex : "##{hex}"
  end

  def preset_label
    PRESET_COLORS.key(normalized_hex.upcase) || normalized_hex
  end

  def ready?
    status == "ready"
  end

  def failed?
    status == "failed"
  end
end
