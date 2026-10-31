# frozen_string_literal: true

module PlatformOauth
  class AuthorizationsController < ApplicationController
    layout "admin_platform"
    before_action :prevent_caching

    def show
      @ticket = params[:ticket]
      @query = @ticket.present? ? Oauth::Tickets.read(@ticket) : initial_query
      return invalid_request unless valid_query?

      @ticket ||= Oauth::Tickets.issue(@query)
      return unless authorize_actor

      @client = oauth_client
    end

    def create
      @ticket = params[:ticket]
      @query = Oauth::Tickets.read(@ticket)
      return invalid_request unless valid_query?
      return unless authorize_actor

      if params[:decision] == "deny"
        return redirect_to callback_url(error: "access_denied"), allow_other_host: true, status: :see_other
      end
      return invalid_request unless params[:decision] == "allow"

      code = PlatformOauthCode.issue!(
        user: current_admin_user, client_id: oauth_client.client_id,
        redirect_uri: @query[:redirect_uri], code_challenge: @query[:code_challenge], resource: resource
      )
      redirect_to callback_url(code: code), allow_other_host: true, status: :see_other
    end

    private

    def prevent_caching
      response.set_header("Cache-Control", "no-store")
      response.set_header("Referrer-Policy", "no-referrer")
    end

    def resource
      "#{request.base_url}/platform/mcp"
    end

    def initial_query
      params.permit(:client_id, :redirect_uri, :response_type, :code_challenge, :code_challenge_method, :state, :scope, :resource)
        .to_h.symbolize_keys.merge(platform_oauth: true)
    end

    def valid_query?
      @query && @query[:platform_oauth] == true &&
        oauth_client&.allows_redirect?(@query[:redirect_uri]) &&
        @query[:response_type] == "code" &&
        @query[:code_challenge_method] == "S256" &&
        @query[:code_challenge].to_s.match?(/\A[A-Za-z0-9_-]{43}\z/) &&
        (@query[:scope].blank? || @query[:scope] == "platform") &&
        (@query[:resource].blank? || @query[:resource] == resource)
    end

    def oauth_client
      OauthClient.find_by(client_id: @query&.dig(:client_id))
    end

    def authorize_actor
      unless current_admin_user
        session[:return_to] = platform_oauth_authorize_path(ticket: @ticket)
        redirect_to admin_login_path
        return false
      end
      unless current_admin_user.active? && current_admin_user.super_admin?
        render :forbidden, status: :forbidden
        return false
      end
      true
    end

    def invalid_request
      render :invalid, status: :bad_request
    end

    def callback_url(extra)
      uri = URI.parse(@query[:redirect_uri])
      extra[:state] = @query[:state] if @query[:state].present?
      uri.query = [ uri.query, extra.to_query ].compact_blank.join("&")
      uri.to_s
    end
  end
end
