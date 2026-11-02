# frozen_string_literal: true

# Append-only record of who accessed buyer personal data and through which surface.
# It stores identifiers and counts only, never the personal data itself.
class AuditEvent < ApplicationRecord
  SOURCES = %w[ui api mcp job system].freeze

  belongs_to :store, optional: true
  belongs_to :actor_user, class_name: "User", optional: true
  belongs_to :subject, polymorphic: true, optional: true

  validates :action, presence: true
  validates :source, inclusion: { in: SOURCES }

  scope :personal_data_reads, -> { where(action: PersonalDataAudit::ACTION) }

  # Written once; tampering through the model is refused.
  def readonly?
    persisted? || super
  end

  before_destroy { raise ActiveRecord::ReadOnlyRecord, "audit events are append-only" }
end
