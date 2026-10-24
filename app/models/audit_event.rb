# frozen_string_literal: true

# Append-only record of who did what. actor_label survives staff deletion.
class AuditEvent < ApplicationRecord
  SOURCES = %w[ui api mcp job system].freeze
  SECRET_KEYS = /pass|token|secret|phone|otp/i

  belongs_to :store, optional: true
  belongs_to :actor_user, class_name: "User", optional: true

  validates :action, presence: true
  validates :source, inclusion: { in: SOURCES }

  before_validation { self.metadata = self.class.redact(metadata) }
  before_destroy { throw :abort }

  def readonly? = persisted?

  def self.redact(value)
    case value
    when Hash then value.to_h { |k, v| [ k.to_s, k.to_s.match?(SECRET_KEYS) ? "[FILTERED]" : redact(v) ] }
    when Array then value.map { |v| redact(v) }
    else value
    end
  end
end
