# frozen_string_literal: true

# Logs successful views of admin screens that show buyer names, phones or addresses.
# New screens that render buyer contact details must be added to SCREENS.
module PersonalDataAccessLogging
  extend ActiveSupport::Concern

  SCREENS = {
    "admin/orders" => %w[index show edit packing_slip sendit_label],
    "admin/customers" => %w[index show edit],
    "admin/confirmations" => %w[index home desk],
    "admin/delivery" => %w[show],
    "admin/dashboard" => %w[show]
  }.freeze

  included do
    after_action :record_personal_data_access
  end

  private

  def record_personal_data_access
    return unless SCREENS.fetch(controller_path, []).include?(action_name)
    return unless response.successful? && current_store && current_user

    PersonalDataAudit.record(
      store: current_store, source: "ui", surface: "#{controller_path}##{action_name}",
      actor_user: current_user, actor_label: current_user.email, ip: request.remote_ip,
      subject: audited_subject, acting_as_platform: current_user.super_admin? && current_user.store_id != current_store.id
    )
  end

  def audited_subject
    [ @order, @customer ].find { |record| record.respond_to?(:persisted?) && record.persisted? }
  end
end
