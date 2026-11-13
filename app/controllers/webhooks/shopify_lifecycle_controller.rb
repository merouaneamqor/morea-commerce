# frozen_string_literal: true

module Webhooks
  class ShopifyLifecycleController < ActionController::API
    wrap_parameters false

    def uninstall
      Connections::ShopifyLifecycle.uninstall!(body: request.raw_post, headers: request.headers)
      head :ok
    rescue Connections::ShopifyLifecycle::Error => error
      render json: { error: error.message }, status: error.status
    end
  end
end
