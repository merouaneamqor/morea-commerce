# frozen_string_literal: true

module Oauth
  class RegistrationsController < ActionController::API
    include Cors

    def preflight
      head :no_content
    end

    def create
      client = OauthClient.register!(
        name: params[:client_name],
        redirect_uris: params[:redirect_uris]
      )
      render json: {
        client_id: client.client_id,
        client_name: client.client_name,
        redirect_uris: client.redirect_uris,
        grant_types: [ "authorization_code", "refresh_token" ],
        response_types: [ "code" ],
        token_endpoint_auth_method: "none",
        client_id_issued_at: client.created_at.to_i
      }, status: :created
    rescue ArgumentError => error
      render json: { error: "invalid_client_metadata", error_description: error.message }, status: :bad_request
    end
  end
end
