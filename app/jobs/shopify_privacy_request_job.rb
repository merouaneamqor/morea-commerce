# frozen_string_literal: true

class ShopifyPrivacyRequestJob < ApplicationJob
  queue_as :default
  retry_on ActiveRecord::Deadlocked, wait: :polynomially_longer, attempts: 5

  def perform(request_id)
    ShopifyPrivacyRequest.find_by(id: request_id)&.process!
  end
end
