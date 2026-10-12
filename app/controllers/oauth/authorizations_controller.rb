# frozen_string_literal: true

module Oauth
  class AuthorizationsController < ApplicationController
    layout "admin"

    def show
      @query = oauth_query
      unless oauth_client&.allows_redirect?(@query[:redirect_uri])
        render :invalid, status: :bad_request
        return
      end
      @query[:code_challenge_method] = "S256" if @query[:code_challenge_method].blank?
      unless @query[:code_challenge].present? && @query[:code_challenge_method] == "S256"
        render :invalid, status: :bad_request
        return
      end
      unless current_store
        render :missing_store, status: :bad_request
        return
      end
      unless current_admin_user
        session[:return_to] = request.fullpath
        redirect_to admin_login_path
        return
      end

      @client = oauth_client
      @store = current_store
    end

    def create
      query = session_query
      client = OauthClient.find_by(client_id: query[:client_id])
      unless client&.allows_redirect?(query[:redirect_uri]) && current_store && current_admin_user
        redirect_to admin_login_path, alert: "Sign in on your store to connect an agent."
        return
      end

      code = Codes.issue(
        store: current_store,
        client_id: client.client_id,
        redirect_uri: query[:redirect_uri],
        code_challenge: query[:code_challenge]
      )
      session.delete(:oauth_query)
      redirect_to callback_url(query[:redirect_uri], code: code, state: query[:state]), allow_other_host: true
    end

    private

    def oauth_query
      query = params.permit(:client_id, :redirect_uri, :code_challenge, :code_challenge_method, :state, :scope, :resource).to_h.symbolize_keys
      session[:oauth_query] = query
      query
    end

    def session_query
      (session[:oauth_query] || {}).symbolize_keys
    end

    def oauth_client
      OauthClient.find_by(client_id: @query[:client_id])
    end

    def callback_url(redirect_uri, code:, state:)
      uri = URI.parse(redirect_uri)
      extra = { code: code }
      extra[:state] = state if state.present?
      uri.query = [ uri.query, extra.to_query ].compact_blank.join("&")
      uri.to_s
    end
  end
end
