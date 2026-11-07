# frozen_string_literal: true

module Admin
  # Sends the signed-in workspace to YouCan for approval, then stores the
  # connected boutique. The authorization code is exchanged once and is not kept.
  class YoucanConnectionsController < BaseController
    STATE_PATTERN = /\A[0-9a-f]{48}\z/
    STATE_TTL = 10.minutes

    prepend_before_action :remember_connection_request, only: :show
    before_action -> { head :not_found unless current_store }

    def show
      unless Connections::YoucanOauth.configured?
        response.headers["Cache-Control"] = "no-store"
        return render :unavailable, status: :service_unavailable
      end

      state = pending_state || SecureRandom.hex(24)
      session[:youcan_oauth] = {
        "state" => state,
        "digest" => Digest::SHA256.hexdigest(state),
        "expires_at" => STATE_TTL.from_now.iso8601
      }
      response.headers["Cache-Control"] = "no-store"
      redirect_to Connections::YoucanOauth.authorization_url(state: state), allow_other_host: true
    end

    def callback
      response.headers["Cache-Control"] = "no-store"
      if params[:error].present?
        session.delete(:youcan_oauth)
        return redirect_to admin_store_connections_path, alert: t("connections.youcan_oauth.denied")
      end
      return redirect_to admin_store_connections_path, alert: t("connections.youcan_oauth.invalid") unless consume_state!

      connection = Connections::YoucanOauth.connect!(store: current_store, code: authorization_code)
      redirect_to admin_store_connection_path(connection), notice: t("connections.youcan_oauth.connected")
    rescue Connections::YoucanOauth::Error => error
      Rails.logger.warn("YouCan connection failed: #{error.code}")
      redirect_to admin_store_connections_path, alert: t("connections.youcan_oauth.failed")
    end

    private

    def consume_state!
      pending = session.delete(:youcan_oauth)
      return false unless pending.is_a?(Hash)

      given = params[:state].to_s
      expires_at = Time.iso8601(pending["expires_at"].to_s)
      digest = pending["digest"].to_s
      return false unless given.match?(STATE_PATTERN) && expires_at.future? && digest.bytesize == 64

      ActiveSupport::SecurityUtils.secure_compare(Digest::SHA256.hexdigest(given), digest)
    rescue ArgumentError
      false
    end

    def pending_state
      pending = session[:youcan_oauth]
      return unless pending.is_a?(Hash)

      state = pending["state"].to_s
      expires_at = Time.iso8601(pending["expires_at"].to_s)
      state if state.match?(STATE_PATTERN) && expires_at.future?
    rescue ArgumentError
      nil
    end

    # Rack treats a raw "+" in the query as a space. YouCan's code can contain
    # "+", so read it from the query string and keep that character.
    def authorization_code
      pair = request.query_string.to_s.split("&").find { |part| part.start_with?("code=") }
      return params[:code].to_s unless pair

      CGI.unescape(pair.delete_prefix("code=").gsub("+", "%2B"))
    end

    def remember_connection_request
      return if current_admin_user

      session[:return_to] = request.fullpath
    end
  end
end
