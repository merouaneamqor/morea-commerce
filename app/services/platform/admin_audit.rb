# frozen_string_literal: true

module Platform
  # Append-only audit for privileged platform actions (billing, impersonation,
  # feature flags, workspace resets, staff lifecycle). Never stores secrets or PII
  # payloads; identifiers and short scalars only.
  class AdminAudit
    METADATA_KEYS = %i[
      surface outcome invoice_number payment_reference flag enabled
      lifecycle role slug confirmation_present connection_id provider
      privacy_request_id reason count
    ].freeze

    def self.record(action:, actor:, source: "ui", store: nil, subject: nil, ip: nil, **metadata)
      AuditEvent.create!(
        store: store,
        actor_user: actor,
        actor_label: actor&.email.to_s.first(80).presence,
        source: source,
        acting_as_platform: true,
        action: action.to_s,
        subject: subject,
        ip: ip.to_s.first(64).presence,
        metadata: safe_metadata(metadata)
      )
    rescue StandardError => error
      Rails.error.report(error, handled: true, context: { action: action })
      nil
    end

    def self.safe_metadata(values)
      values.compact.slice(*METADATA_KEYS).transform_values do |value|
        value.is_a?(Numeric) || value == true || value == false ? value : value.to_s.first(120)
      end
    end
  end
end
