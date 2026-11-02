module Admin
  # The WordPress plugin sends the merchant's browser here with the site, an opaque
  # state, a PKCE challenge and its callback. Staff confirm on this page, then
  # Morea redirects back with a one-time code. Nothing is copied or pasted.
  class WoocommerceConnectionsController < BaseController
    STATE_MAX_BYTES = 1024
    CHALLENGE_PATTERN = /\A[A-Za-z0-9\-_]{43}\z/
    # Optional subdirectory segments (never dot-only), then WordPress' own admin-post endpoint.
    CALLBACK_PATH = %r{\A(?:/(?!\.+(?:/|\z))[A-Za-z0-9._~-]+)*/wp-admin/admin-post\.php\z}
    CALLBACK_QUERY = "action=seallo_wc_callback"

    prepend_before_action :remember_connection_request, only: :show
    before_action -> { head :not_found unless current_store }

    def show
      values = connection_request
      return head :bad_request unless values
      raise ActiveRecord::RecordNotFound unless WoocommerceConnectionCode.authorized?(store: current_store, user: current_user)

      @request_values = values
      response.headers["Cache-Control"] = "no-store"
    end

    # Minting happens only on this POST, so a cross-site page cannot make a
    # merchant's browser create a code by navigating to a URL.
    def create
      values = connection_request
      return head :bad_request unless values

      code = WoocommerceConnectionCode.issue!(store: current_store, user: current_user, site: values[:site], code_challenge: values[:code_challenge])
      response.headers["Cache-Control"] = "no-store"
      # head avoids Rails' "Redirected to" request log, which would record the code.
      head :found, location: "#{values[:return_to]}&#{URI.encode_www_form(code: code, state: values[:state])}"
    end

    private

    # return_to must be the plugin's own callback on the very site being connected,
    # so a code can only ever be delivered to the origin shown on the confirmation page.
    def connection_request
      site = string_param(:site)
      state = string_param(:state)
      challenge = string_param(:code_challenge)
      return_to = string_param(:return_to)
      return unless site && site.bytesize <= 253 && site.match?(Connections::WoocommerceConnect::SITE_PATTERN)
      return unless state.present? && state.bytesize <= STATE_MAX_BYTES
      return unless challenge&.match?(CHALLENGE_PATTERN)
      return unless callback_for?(return_to, site)

      { site: site, state: state, code_challenge: challenge, return_to: return_to }
    end

    def callback_for?(return_to, site)
      return false unless return_to
      uri = URI.parse(return_to)
      uri.is_a?(URI::HTTPS) && uri.host == site && uri.port == 443 && uri.userinfo.nil? && uri.fragment.nil? &&
        uri.path.match?(CALLBACK_PATH) && uri.query == CALLBACK_QUERY
    rescue URI::InvalidURIError
      false
    end

    def connection_request_present?
      params.key?(:site) || params.key?(:state) || params.key?(:return_to) || params.key?(:code_challenge)
    end

    def string_param(key)
      value = params[key]
      value if value.is_a?(String)
    end

    # Sign-in redirects back here after login. Only the authorization query is kept.
    def remember_connection_request
      return if current_admin_user || !connection_request_present?

      session[:return_to] = request.fullpath
    end
  end
end
