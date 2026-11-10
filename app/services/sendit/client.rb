# frozen_string_literal: true

require "net/http"
require "json"

module Sendit
  # Thin wrapper over https://app.sendit.ma/api/v1 (bearer token from /login, cached)
  class Client
    # `kind` tells the failures apart (set by the login check):
    #   :invalid_keys - Sendit's API answered 401/422, the keys are refused
    #   :blocked      - Cloudflare in front of Sendit answered with its challenge page (HTTP 403, HTML): the API never saw the keys
    #   :network      - timeout, DNS, TLS or connection failure before any answer
    #   :unexpected   - an answer that is not Sendit's API format (HTML, no token, 5xx)
    #   :rejected     - Sendit's API refused with another 4xx and a message
    # `detail` is a short, safe description (status, server, page title, exception class); it never contains the keys.
    class Error < StandardError
      attr_reader :status, :body, :kind, :detail

      def initialize(message, status: nil, body: nil, kind: nil, detail: nil)
        super(message)
        @status = status
        @body = body
        @kind = kind
        @detail = detail
      end
    end

    def self.configured?(store)
      store&.sendit_configured?
    end

    # Checks a pair of keys against Sendit's login (POST /login). Raises Error when they are refused or Sendit is unreachable.
    # The workspace's cached session is not touched.
    def self.verify!(store, public_key:, secret_key:)
      new(store, credentials: { public_key: public_key, secret_key: secret_key }).login!
    end

    def initialize(store, credentials: nil)
      @store = store
      @credentials = credentials
      raise ArgumentError, "Store is required" unless @store
    end

    # Returns the bearer token Sendit issues for the keys.
    def login!
      keys = @credentials || { public_key: store.sendit_public_key, secret_key: store.sendit_secret_key }
      response = perform(:post, URI.join(base_url, "login"), { public_key: keys[:public_key], secret_key: keys[:secret_key] }, nil)
      parse!(response).dig("data", "token").presence ||
        raise(Error.new("Sendit login returned no token", status: response.code.to_i, kind: :unexpected, detail: "HTTP #{response.code}, no token in the answer"))
    rescue Error => error
      log_login_failure(error, keys)
      raise
    end

    def base_url
      ENV.fetch("SENDIT_API_URL", "https://app.sendit.ma/api/v1/").chomp("/") + "/"
    end

    # Responses are usually wrapped in "data", but not always (e.g. getlabels)
    def create_delivery(attrs) = unwrap(request(:post, "deliveries", attrs))
    def update_delivery(code, attrs) = unwrap(request(:put, "deliveries/#{code}", attrs))
    def delivery(code) = unwrap(request(:get, "deliveries/#{code}"))
    def delete_delivery(code) = request(:delete, "deliveries/#{code}")
    def labels(codes, thermal: true) = unwrap(request(:post, "deliveries/getlabels", { codesToPrint: Array(codes).join(","), printFormat: thermal ? 1 : 0 }))
    def districts(page: 1, query: nil) = request(:get, "districts", nil, { page: page, querystring: query }.compact)
    
    def pickup_cities
      response = request(:get, "districts/pickup-cities")
      data = response["data"] || response
      Array(data).map { |city| city.is_a?(Hash) ? city : nil }.compact
    rescue Error => e
      Rails.logger.warn("[Sendit] pickup_cities failed: #{e.message}")
      []
    end
    # Official delivery status codes → French labels (GET /all-status-deliveries)
    def all_status_deliveries
      data = request(:get, "all-status-deliveries")["data"]
      data.is_a?(Hash) ? data.transform_keys { |k| k.to_s.upcase } : {}
    end

    private

    attr_reader :store

    def token_cache_key
      "sendit:token:store:#{store.id}"
    end

    def unwrap(json)
      json["data"].is_a?(Hash) ? json["data"] : json
    end

    def request(method, path, body = nil, query = nil, retried: false)
      uri = URI.join(base_url, path)
      uri.query = URI.encode_www_form(query) if query.present?

      response = perform(method, uri, body, token)
      if response.code.to_i == 401 && !retried
        Rails.cache.delete(token_cache_key)
        return request(method, path, body, query, retried: true)
      end

      parse!(response)
    end

    def token
      return login! if @credentials

      Rails.cache.fetch(token_cache_key, expires_in: 6.hours) { login! }
    end

    def perform(method, uri, body, bearer)
      klass = { get: Net::HTTP::Get, post: Net::HTTP::Post, put: Net::HTTP::Put, delete: Net::HTTP::Delete }.fetch(method)
      req = klass.new(uri)
      req["Accept"] = "application/json"
      req["Content-Type"] = "application/json"
      req["Authorization"] = "Bearer #{bearer}" if bearer
      req.body = body.to_json if body

      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 10, read_timeout: 30) do |http|
        http.request(req)
      end
    rescue SocketError, Timeout::Error, IOError, EOFError, SystemCallError, OpenSSL::SSL::SSLError => e
      raise Error.new("Sendit unreachable: #{e.message}", kind: :network, detail: e.class.name)
    end

    def parse!(response)
      parsed = begin
        JSON.parse(response.body.presence || "{}")
      rescue JSON::ParserError
        nil
      end
      json = parsed.is_a?(Hash) ? parsed : {}
      ok = response.code.to_i.between?(200, 299) && json["success"] != false
      return json if ok

      message = json["message"].presence || json["error"].presence || "HTTP #{response.code}"
      # Field errors come back under "errors" or "data" ({ "pickup_district_id" => "… est obligatoire." })
      details = [ json["errors"], json["data"] ].find { |v| v.is_a?(Hash) }
      errors = details&.values&.flatten&.join(" ")
      raise Error.new([ message, errors ].compact_blank.join(" — "), status: response.code.to_i, body: json,
        kind: failure_kind(response, parsed), detail: failure_detail(response, json))
    end

    # Cloudflare's challenge or block page answers 403 (or 429/503) in HTML before the request reaches Sendit's API.
    def cloudflare_block?(response)
      response["server"].to_s.casecmp?("cloudflare") && (response["cf-mitigated"].present? || response["content-type"].to_s.include?("html"))
    end

    def failure_kind(response, parsed)
      status = response.code.to_i
      return :blocked if cloudflare_block?(response)
      return :invalid_keys if [ 401, 422 ].include?(status)
      return :unexpected if parsed.nil? || status >= 500

      :rejected
    end

    def failure_detail(response, json)
      parts = [ "HTTP #{response.code}" ]
      parts << "Cloudflare" if response["server"].to_s.casecmp?("cloudflare")
      title = response.body.to_s[%r{<title>\s*(.*?)\s*</title>}mi, 1]
      parts << "« #{title.squish.first(80)} »" if title.present?
      parts << json["message"].to_s.squish.first(120) if json["message"].present?
      parts << "cf-ray #{response['cf-ray']}" if response["cf-ray"].present?
      parts.join(" · ")
    end

    # One line for the log: what failed and what Sendit answered, never the keys.
    def log_login_failure(error, keys)
      secrets = [ keys&.dig(:public_key), keys&.dig(:secret_key) ].compact_blank
      line = "[Sendit login] store=#{store.slug} kind=#{error.kind.inspect} status=#{error.status.inspect} detail=#{error.detail.inspect} message=#{error.message.to_s.first(200).inspect}"
      secrets.each { |secret| line = line.gsub(secret, "[FILTERED]") }
      Rails.logger.warn(line)
    end
  end
end
