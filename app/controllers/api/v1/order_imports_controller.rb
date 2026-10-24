# frozen_string_literal: true

module Api
  module V1
    # Store API/OAuth tokens select the tenant. A body-supplied store is never used.
    class OrderImportsController < ActionController::API
      include Api::TokenAuthenticatable
      wrap_parameters false

      def create
        payload = request.request_parameters
        unknown = payload.keys - %w[source external_id order]
        raise Orders::Intake::Error, "Unknown request fields." if unknown.any?

        result = Orders::Intake.new(store: current_api_store).call(
          source: payload["source"], external_id: payload["external_id"], attrs: payload["order"]
        )
        render json: {
          order: { id: result.order.id, number: result.order.number, status: result.order.status },
          created: result.created?, replayed: result.replayed?
        }, status: result.created? ? :created : :ok
      rescue Orders::Intake::Error => error
        render json: { error: { type: "invalid_request", message: error.message } }, status: :unprocessable_entity
      end
    end
  end
end
