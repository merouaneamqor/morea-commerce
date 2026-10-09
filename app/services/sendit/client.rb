# frozen_string_literal: true

require "net/http"
require "json"

module Sendit
  # Thin wrapper over https://app.sendit.ma/api/v1 (bearer token from /login, cached)
  class Client
    class Error < StandardError
      attr_reader :status, :body

      def initialize(message, status: nil, body: nil)
        super(message)
        @status = status
        @body = body
      end
    end

    def self.configured?(store)
      store&.sendit_configured?
    end

    def initialize(store)
      @store = store
      raise ArgumentError, "Store is required" unless @store
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
    def pickup_cities = Array(request(:get, "districts/pickup-cities")["data"])
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
      Rails.cache.fetch(token_cache_key, expires_in: 6.hours) do
        response = perform(:post, URI.join(base_url, "login"),
                           { public_key: store.sendit_public_key, secret_key: store.sendit_secret_key }, nil)
        parse!(response).dig("data", "token").presence || raise(Error.new("Sendit login returned no token"))
      end
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
    rescue SocketError, Timeout::Error, Errno::ECONNREFUSED, OpenSSL::SSL::SSLError => e
      raise Error.new("Sendit unreachable: #{e.message}")
    end

    def parse!(response)
      json = JSON.parse(response.body.presence || "{}") rescue {}
      ok = response.code.to_i.between?(200, 299) && json["success"] != false
      return json if ok

      message = json["message"].presence || json["error"].presence || "HTTP #{response.code}"
      # Field errors come back under "errors" or "data" ({ "pickup_district_id" => "… est obligatoire." })
      details = [ json["errors"], json["data"] ].find { |v| v.is_a?(Hash) }
      errors = details&.values&.flatten&.join(" ")
      raise Error.new([ message, errors ].compact_blank.join(" — "), status: response.code.to_i, body: json)
    end
  end
end
