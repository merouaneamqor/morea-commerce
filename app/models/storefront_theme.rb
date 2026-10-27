# frozen_string_literal: true

class StorefrontTheme < ApplicationRecord
  STATUSES = %w[draft published].freeze

  belongs_to :store

  validates :name, :catalog_key, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :snapshot, presence: true
  validate :snapshot_has_sections

  scope :draft, -> { where(status: "draft") }
  scope :published, -> { where(status: "published") }

  def draft?
    status == "draft"
  end

  def published?
    status == "published"
  end

  private

  def snapshot_has_sections
    return if snapshot.is_a?(Hash) && snapshot["sections"].is_a?(Array)

    errors.add(:snapshot, "must contain a sections array")
  end
end
