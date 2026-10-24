# frozen_string_literal: true

module Audit
  module_function

  # Never raises into the caller's request: an audit failure is logged, not a user-facing error.
  def record(action, actor: nil, store: nil, source: "ui", subject: nil, request: nil, platform: nil, metadata: {})
    AuditEvent.create!(
      action: action,
      store: store,
      actor_user: actor,
      actor_label: actor && (actor.name.presence || actor.email),
      source: source,
      acting_as_platform: platform.nil? ? !!(actor&.super_admin?) : platform,
      subject_type: subject&.class&.name,
      subject_id: subject&.id,
      metadata: metadata,
      ip: request&.remote_ip
    )
  rescue StandardError => e
    Rails.logger.error("audit failure for #{action}: #{e.class}")
    nil
  end

  def email_digest(email) = Digest::SHA256.hexdigest(email.to_s.strip.downcase)
end
