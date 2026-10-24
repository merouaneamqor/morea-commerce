# frozen_string_literal: true

class AccessRequestNotifyJob < ApplicationJob
  queue_as :default
  retry_on StandardError, wait: :polynomially_longer, attempts: 5

  def perform(access_request_id)
    access_request = AccessRequest.find_by(id: access_request_id)
    return unless access_request&.pending?

    DiscordNotifier.notify_access_request(access_request)
  end
end
