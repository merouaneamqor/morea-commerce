# frozen_string_literal: true

class ProductColorway < ApplicationRecord
  belongs_to :product
  belongs_to :source_attachment, class_name: "ActiveStorage::Attachment"
  has_one_attached :image
  has_one_attached :mask

  validates :name, :hex, presence: true
  validates :hex, format: { with: /\A#[0-9A-F]{6}\z/, message: "must be a hex color" }
  validate :source_image_belongs_to_product

  def summary
    report["summary"].presence if report.is_a?(Hash)
  end

  private

  def source_image_belongs_to_product
    attachment = source_attachment
    return if attachment&.record_type == "Product" && attachment.record_id == product_id && attachment.name == "images"

    errors.add(:base, "Choose one of this product's photos.")
  end
end
