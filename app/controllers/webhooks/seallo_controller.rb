# frozen_string_literal: true

module Webhooks
  class SealloController < ActionController::API
    wrap_parameters false

    def create
      result = Connections::SealloWebhooks.call(body: request.raw_post, headers: request.headers)
      render json: result
    rescue Connections::SealloWebhooks::Error, Connections::WebhookIntake::Error => error
      render json: { error: error.message }, status: error.status
    end
  end
end
