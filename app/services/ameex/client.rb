# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module Ameex
  # Thin wrapper over https://api.ameex.app/customer
  # Headers: C-Api-Id + C-Api-Key. DeliveryAccount: api_key = Id, api_secret = Key.
  # Successful answers look like { "login" => "success", "api" => { "type" => "success", ... } }.
  class Client
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
      store&.ameex_configured?
    end

    def self.verify!(store, api_id:, api_key:)
      new(store, credentials: { api_id: api_id, api_key: api_key }).cities
      true
    end

    def initialize(store, credentials: nil)
      @store = store
      @credentials = credentials
      raise ArgumentError, "Store is required" unless @store
    end

    def base_url
      ENV.fetch("AMEEX_API_URL", "https://api.ameex.app/customer").chomp("/")
    end

    # { "1" => { "id" => 1, "name" => "Marrakech" }, ... }
    def cities
      json = request(:get, "Delivery/Cities")
      json.dig("api", "cities") || {}
    end

    # { "DELIVERED" => { "name" => "Livré", "color" => "...", "type" => "fixed" }, ... }
    def statuses
      json = request(:get, "Delivery/Parcels/Statuts")
      json.dig("api", "data", "status") || {}
    end

    # { "code" => "SBX-…", "sandbox" => 1 }
    def add_parcel(attrs)
      json = request(:post, "Delivery/Parcels/Action/Type/Add", attrs)
      data = json.dig("api", "data")
      data = {} unless data.is_a?(Hash)
      data.merge("msg" => json.dig("api", "msg"), "sandbox" => json.dig("api", "sandbox")).compact
    end

    # Latest tracking event as a hash with statut / statut_name / comment.
    def tracking(code)
      json = request(:get, "Delivery/Parcels/Tracking/ParcelCode/#{CGI.escape(code.to_s)}")
      events = json.dig("api", "tracking")
      event = Array(events).last
      event.is_a?(Hash) ? event : {}
    end

    def mass_tracking(codes)
      json = request(:post, "Delivery/Parcels/MassTracking", { codes: Array(codes).first(100).join(",") })
      json.dig("api", "tracking") || {}
    end

    def mass_info(codes)
      json = request(:post, "Delivery/Parcels/MassInfo", { codes: Array(codes).first(100).join(",") })
      json.dig("api", "parcels") || {}
    end

    def parcel_info(code)
      row = mass_info([ code ])[code.to_s]
      row.is_a?(Hash) ? row : {}
    end

    private

    attr_reader :store

    def keys
      return @credentials if @credentials

      { api_id: store.ameex_api_id, api_key: store.ameex_api_key }
    end

    def request(method, path, fields = nil)
      uri = URI("#{base_url}/#{path}")
      parse!(perform(method, uri, fields))
    rescue Error => error
      log_failure(error, path)
      raise
    end

    def perform(method, uri, fields)
      klass = { get: Net::HTTP::Get, post: Net::HTTP::Post }.fetch(method)
      req = klass.new(uri)
      req["Accept"] = "application/json"
      req["C-Api-Id"] = keys[:api_id].to_s
      req["C-Api-Key"] = keys[:api_key].to_s
      if fields.present?
        req.set_form(fields.transform_keys(&:to_s).transform_values { |v| v.nil? ? "" : v.to_s }, "multipart/form-data")
      end
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 10, read_timeout: 30) do |http|
        http.request(req)
      end
    rescue SocketError, Timeout::Error, IOError, EOFError, SystemCallError, OpenSSL::SSL::SSLError => e
      raise Error.new("Ameex unreachable: #{e.message}", kind: :network, detail: e.class.name)
    end

    def parse!(response)
      parsed = begin
        JSON.parse(response.body.presence || "{}")
      rescue JSON::ParserError
        nil
      end
      json = parsed.is_a?(Hash) ? parsed : {}
      status = response.code.to_i

      if login_error?(json)
        raise Error.new("Ameex refused these credentials", status: status, body: json, kind: :invalid_keys, detail: "HTTP #{status} · login error")
      end

      api = json["api"]
      if json["login"].to_s == "success" && api.is_a?(Hash)
        return json if api["type"].to_s == "success" || api["type"].blank?

        message = api["msg"].presence || "Ameex API error"
        raise Error.new(message.to_s, status: status, body: json, kind: :rejected, detail: "HTTP #{status} · #{message}")
      end

      ok = status.between?(200, 299) && json["success"] != false
      return json if ok

      message = json["message"].presence || json["error"].presence || "HTTP #{status}"
      raise Error.new(message.to_s, status: status, body: json,
        kind: failure_kind(response, parsed, json), detail: failure_detail(response, json))
    end

    def login_error?(json)
      return true if json["login"].to_s == "error"

      data = json["data"]
      data.is_a?(Hash) && data["pg_title"].to_s.downcase.include?("connexion")
    end

    def cloudflare_block?(response)
      response["server"].to_s.casecmp?("cloudflare") && (response["cf-mitigated"].present? || response["content-type"].to_s.include?("html"))
    end

    def failure_kind(response, parsed, json)
      status = response.code.to_i
      return :blocked if cloudflare_block?(response)
      return :invalid_keys if login_error?(json) || [ 401, 403, 422 ].include?(status)
      return :unexpected if parsed.nil? || status >= 500

      :rejected
    end

    def failure_detail(response, json)
      parts = [ "HTTP #{response.code}" ]
      parts << "Cloudflare" if response["server"].to_s.casecmp?("cloudflare")
      msg = json.dig("api", "msg") || json["message"] || json["error"]
      parts << msg.to_s.squish.first(120) if msg.present?
      parts.join(" · ")
    end

    def log_failure(error, path)
      secrets = [ keys[:api_id], keys[:api_key] ].compact_blank
      line = "[Ameex] store=#{store.slug} path=#{path} kind=#{error.kind.inspect} status=#{error.status.inspect} detail=#{error.detail.inspect} message=#{error.message.to_s.first(200).inspect}"
      secrets.each { |secret| line = line.gsub(secret.to_s, "[FILTERED]") }
      Rails.logger.warn(line)
    end
  end
end
