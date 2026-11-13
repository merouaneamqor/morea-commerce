# frozen_string_literal: true

require "net/http"
require "json"

module Connections
  # Starts YouCan's authorization-code flow and turns the approval into one
  # store connection. YouCan signs later order.created deliveries with this
  # app's client secret, which is stored encrypted on the connection.
  class YoucanOauth
    AUTHORIZE_URL = "https://seller-area.youcan.shop/admin/oauth/authorize"
    TOKEN_URL = "https://api.youcan.shop/oauth/token"
    STORE_URL = "https://api.youcan.shop/me"
    SUBSCRIBE_URL = "https://api.youcan.shop/resthooks/subscribe"
    SCOPES = %w[view-store-info edit-rest-hooks].freeze
    HOSTNAME = /\A[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?\z/
    STORE_ID = /\A[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\z/
    # YouCan returns a one-time code that can contain base64 characters.
    CODE = /\A[A-Za-z0-9\-._~+\/=]{8,2048}\z/
    MAX_BODY_BYTES = 65_536

    class Error < StandardError
      def initialize(code = "unavailable")
        super("YouCan connection failed")
        @code = code
      end

      attr_reader :code
    end

    def self.configured?
      client_id.present? && client_secret.present? && client_secret.bytesize >= 16
    end

    def self.client_id
      ENV["YOUCAN_CLIENT_ID"].to_s
    end

    def self.client_secret
      ENV["YOUCAN_CLIENT_SECRET"].to_s
    end

    def self.callback_url
      "#{Store.platform_origin}/admin/youcan/callback"
    end

    def self.authorization_url(state:)
      query = URI.encode_www_form(client_id: client_id, redirect_uri: callback_url, response_type: "code", state: state)
      scopes = SCOPES.map { |scope| "scope[]=#{CGI.escape(scope)}" }.join("&")
      "#{AUTHORIZE_URL}?#{query}&#{scopes}"
    end

    def self.connect!(store:, code:, transport: nil)
      new(transport: transport).connect!(store: store, code: code)
    end

    def initialize(transport: nil)
      @transport = transport
    end

    def connect!(store:, code:)
      raise Error, "invalid_code" unless code.is_a?(String) && code.match?(CODE)
      raise Error, "config_missing" unless self.class.configured?

      token = access_token(code)
      info = store_info(token)
      StoreConnection.transaction do
        connection = persist(store, info)
        subscribe(token, connection)
        connection
      end
    end

    private

    def access_token(code)
      payload = post_form(TOKEN_URL, {
        grant_type: "authorization_code",
        client_id: self.class.client_id,
        client_secret: self.class.client_secret,
        redirect_uri: self.class.callback_url,
        code: code
      })
      token = payload["access_token"]
      raise Error, "invalid_token" unless token.is_a?(String) && token.present? && token.bytesize <= 8192 && !token.match?(/[\r\n]/)

      token
    end

    def store_info(token)
      uri = URI(STORE_URL)
      payload = request_json(uri, Net::HTTP::Get.new(uri), token)
      info = payload["id"].present? ? payload : payload["store"] || payload["data"]
      raise Error, "invalid_store" unless info.is_a?(Hash)

      info
    end

    def persist(store, info)
      host = hostname(info)
      store_id = info["id"].to_s.downcase
      raise Error, "invalid_store" unless store_id.match?(STORE_ID) && host.match?(HOSTNAME) && host.bytesize <= 253

      connection = store.store_connections.find_by(provider: "youcan", external_store_id: store_id) ||
        store.store_connections.find_or_initialize_by(provider: "youcan", external_domain: host)
      raise Error, "store_mismatch" if connection.persisted? && connection.external_store_id != store_id

      connection.external_domain = host if connection.new_record?
      connection.external_store_id = store_id if connection.new_record?
      connection.name = display_name(info, host) if connection.new_record?
      connection.assign_attributes(active: true, webhook_secret: self.class.client_secret, verified_at: nil, last_error_code: nil)
      connection.save!
      connection
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      raise Error, "invalid_connection"
    end

    def subscribe(token, connection)
      post_json(SUBSCRIBE_URL, { event: "order.created", target_url: delivery_url(connection) }, token)
    end

    def hostname(info)
      raw = info["domain"].to_s.strip
      host = raw.include?("://") ? URI.parse(raw).host.to_s : raw.split("/").first.to_s
      host = host.downcase.delete_suffix(".").sub(/:\d+\z/, "")
      return host if host.match?(HOSTNAME) && host.bytesize <= 253

      slug = info["slug"].to_s.downcase
      "#{slug}.youcan.store"
    rescue URI::InvalidURIError
      slug = info["slug"].to_s.downcase
      "#{slug}.youcan.store"
    end

    def display_name(info, host)
      info["name"].to_s.strip.presence&.slice(0, 100) || host
    end

    def delivery_url(connection)
      "#{Store.platform_origin}/webhooks/store_orders/#{connection.token}"
    end

    def post_form(url, form)
      uri = URI(url)
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/x-www-form-urlencoded"
      request.body = URI.encode_www_form(form)
      request_json(uri, request)
    end

    def post_json(url, body, token)
      uri = URI(url)
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request.body = JSON.generate(body)
      request_json(uri, request, token)
    end

    def request_json(uri, request, token = nil)
      request["Accept"] = "application/json"
      request["Authorization"] = "Bearer #{token}" if token
      status, body = perform(uri, request)
      raise Error, "invalid_response" if body.bytesize > MAX_BODY_BYTES
      raise Error, "invalid_credentials" if [ 401, 403 ].include?(status)
      raise Error, "unavailable" if status >= 500 || status == 429
      raise Error, oauth_error(body) unless status.between?(200, 299)

      data = JSON.parse(body)
      raise Error, "invalid_response" unless data.is_a?(Hash)

      data
    rescue JSON::ParserError, EncodingError
      raise Error, "invalid_response"
    rescue Timeout::Error, IOError, SystemCallError, SocketError, OpenSSL::SSL::SSLError, Net::HTTPBadResponse, Net::ProtocolError
      raise Error, "unavailable"
    end

    def oauth_error(body)
      data = JSON.parse(body)
      error = data.is_a?(Hash) ? data["error"].to_s : ""
      error.match?(/\A[a-z0-9_]{1,40}\z/) ? error : "invalid_response"
    rescue JSON::ParserError, EncodingError
      "invalid_response"
    end

    def perform(uri, request)
      if @transport
        response = @transport.call(uri, request)
        return [ response.code.to_i, response.body.to_s ]
      end

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 5
      http.read_timeout = 10
      http.write_timeout = 10
      http.max_retries = 0
      response = http.request(request)
      [ response.code.to_i, response.body.to_s ]
    end
  end
end
