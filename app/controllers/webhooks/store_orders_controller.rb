# frozen_string_literal: true

module Webhooks
  class StoreOrdersController < ActionController::API
    wrap_parameters false

    def create
      connection = StoreConnection.find_by!(token: params[:token])
      # WooCommerce's activation probe is unsigned form data. Acknowledge only
      # its documented shape; it never verifies a connection or imports an order.
      if connection.provider == "woocommerce" && connection.active? &&
          request.media_type == "application/x-www-form-urlencoded" &&
          request.raw_post.match?(/\Awebhook_id=[1-9]\d{0,18}\z/)
        return head :ok
      end
      result = Connections::WebhookIntake.new(connection: connection).call(body: request.raw_post, headers: request.headers)
      receipt = result.receipt
      render json: { status: receipt.status, replayed: result.replayed, error: receipt.error_code }, status: receipt.status == "accepted" ? :ok : :unprocessable_entity
    rescue ActiveRecord::RecordNotFound
      head :not_found
    rescue Connections::WebhookIntake::Error => error
      render json: { error: error.message }, status: error.status
    end
  end
end
