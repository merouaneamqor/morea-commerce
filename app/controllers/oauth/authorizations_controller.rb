# frozen_string_literal: true

module Oauth
  class AuthorizationsController < ApplicationController
    layout "admin"

    def show
      @query = resolve_query
      unless valid_query?
        render :invalid, status: :bad_request
        return
      end
      unless current_store
        render :missing_store, status: :bad_request
        return
      end
      unless current_admin_user
        session[:return_to] = oauth_authorize_path(ticket: @ticket)
        redirect_to admin_login_path
        return
      end

      @client = oauth_client
      @store = current_store
    end

    def create
      @query = Tickets.read(params[:ticket])
      @ticket = params[:ticket]
      unless current_store && current_admin_user
        session[:return_to] = oauth_authorize_path(ticket: @ticket) if @ticket.present?
        redirect_to admin_login_path, alert: "Sign in on your store to connect an agent."
        return
      end
      unless valid_query?
        render :invalid, status: :bad_request
        return
      end

      code = Codes.issue(
        store: current_store,
        client_id: oauth_client.client_id,
        redirect_uri: @query[:redirect_uri],
        code_challenge: @query[:code_challenge]
      )
      redirect_to callback_url(@query[:redirect_uri], code: code, state: @query[:state]), allow_other_host: true, status: :see_other
    end

    private

    def resolve_query
      if params[:ticket].present?
        @ticket = params[:ticket]
        Tickets.read(@ticket)
      else
        query = permitted_query
        return if query[:client_id].blank?

        @ticket = Tickets.issue(query)
        query
      end
    end

    def permitted_query
      params.permit(
        :client_id, :redirect_uri, :code_challenge, :code_challenge_method, :state, :scope, :resource
      ).to_h.symbolize_keys
    end

    def valid_query?
      return false unless @query && oauth_client&.allows_redirect?(@query[:redirect_uri])

      @query[:code_challenge_method] = "S256" if @query[:code_challenge_method].blank?
      @query[:code_challenge].present? && @query[:code_challenge_method] == "S256"
    end

    def oauth_client
      OauthClient.find_by(client_id: @query&.dig(:client_id))
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
