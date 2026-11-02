# frozen_string_literal: true

# Records that someone read buyer personal data (names, phones, addresses, emails).
# Called from the admin UI, GraphQL and MCP. A logging failure is reported but never
# blocks the merchant's work, so an audit-table outage cannot stop order handling.
module PersonalDataAudit
  ACTION = "personal_data.read"
  # Only these metadata keys are stored, and only short scalar values.
  METADATA_KEYS = %i[surface operation count kind].freeze

  module_function

  # surface: where the data was shown (e.g. "admin/orders#show", "graphql.customers").
  def record(store:, source:, surface:, actor_user: nil, actor_label: nil, subject: nil, ip: nil, acting_as_platform: false, **metadata)
    AuditEvent.create!(
      store: store, source: source, action: ACTION, actor_user_id: actor_user&.id,
      actor_label: actor_label.to_s.first(80).presence, acting_as_platform: acting_as_platform,
      subject_type: subject&.class&.name, subject_id: subject&.id, ip: ip.to_s.first(64).presence,
      metadata: safe_metadata(metadata.merge(surface: surface))
    )
  rescue StandardError => error
    Rails.error.report(error, handled: true, context: { surface: surface })
    nil
  end

  def safe_metadata(values)
    values.slice(*METADATA_KEYS).transform_values { |value| value.is_a?(Numeric) ? value : value.to_s.first(120) }
  end
end
