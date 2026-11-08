# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module Ozon
  # Thin wrapper over https://api.ozonexpress.ma (customer id + API key in the path).
  # DeliveryAccount credentials: api_key = customer id, api_secret = API key.
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
      store&.ozon_configured?
    end

    # Checks customer id + API key by calling parcel-info. A missing parcel is fine — it proves the keys work.
    def self.verify!(store, customer_id:, api_key:)
      new(store, credentials: { customer_id: customer_id, api_key: api_key }).parcel_info("__seallo_verify__")
      true
    rescue Error => error
      return true if error.kind == :rejected

      raise
    end

    def initialize(store, credentials: nil)
      @store = store
      @credentials = credentials
      raise ArgumentError, "Store is required" unless @store
    end

    def base_url
      ENV.fetch("OZON_API_URL", "https://api.ozonexpress.ma").chomp("/")
    end

    def cities_url
      ENV.fetch("OZON_CITIES_URL", "#{base_url}/cities")
    end

    def pdf_base_url
      ENV.fetch("OZON_PDF_URL", "https://client.ozoneexpress.ma").chomp("/")
    end

    def cities
      parse!(get(URI(cities_url)))
    end

    def add_parcel(attrs)
      request(:post, "add-parcel", attrs)
    end

    def parcel_info(tracking_number)
      request(:post, "parcel-info", { "tracking-number" => tracking_number })
    end

    def tracking(tracking_number)
      request(:post, "tracking", { "tracking-number" => tracking_number })
    end

    # Bulk tracking: JSON body with an array of tracking numbers.
    def tracking_bulk(numbers)
      uri = URI(customer_path("tracking"))
      perform_json(:post, uri, { "tracking-number" => Array(numbers) })
    end

    def add_delivery_note
      request(:post, "add-delivery-note")
    end

    def add_parcel_to_delivery_note(ref:, codes:)
      fields = { "Ref" => ref }
      Array(codes).each_with_index { |code, i| fields["Codes[#{i}]"] = code }
      request(:post, "add-parcel-to-delivery-note", fields)
    end

    def save_delivery_note(ref)
      request(:post, "save-delivery-note", { "Ref" => ref })
    end

    def delivery_note_pdf_url(ref, format: :standard)
      path = case format
      when :tickets then "pdf-delivery-note-tickets"
      when :tickets_4x4 then "pdf-delivery-note-tickets-4-4"
      else "pdf-delivery-note"
      end
      "#{pdf_base_url}/#{path}?dn-ref=#{CGI.escape(ref.to_s)}"
    end

    private

    attr_reader :store

    def keys
      return @credentials if @credentials

      {
        customer_id: store.ozon_customer_id,
        api_key: store.ozon_api_key
      }
    end

    def customer_path(endpoint)
      customer_id = keys[:customer_id].to_s
      api_key = keys[:api_key].to_s
      raise Error.new("Ozon credentials missing", kind: :invalid_keys, detail: "missing customer id or API key") if customer_id.blank? || api_key.blank?

      "#{base_url}/customers/#{CGI.escape(customer_id)}/#{CGI.escape(api_key)}/#{endpoint}"
    end

    def request(method, endpoint, fields = nil)
      uri = URI(customer_path(endpoint))
      parse!(perform_form(method, uri, fields))
    rescue Error => error
      log_failure(error, endpoint)
      raise
    end

    def perform_form(method, uri, fields)
      klass = { get: Net::HTTP::Get, post: Net::HTTP::Post }.fetch(method)
      req = klass.new(uri)
      req["Accept"] = "application/json"
      if fields.present?
        req.set_form(fields.transform_keys(&:to_s).transform_values { |v| v.nil? ? "" : v.to_s }, "multipart/form-data")
      end
      http_start(uri, req)
    rescue SocketError, Timeout::Error, IOError, EOFError, SystemCallError, OpenSSL::SSL::SSLError => e
      raise Error.new("Ozon unreachable: #{e.message}", kind: :network, detail: e.class.name)
    end

    def perform_json(method, uri, body)
      klass = { get: Net::HTTP::Get, post: Net::HTTP::Post }.fetch(method)
      req = klass.new(uri)
      req["Accept"] = "application/json"
      req["Content-Type"] = "application/json"
      req.body = body.to_json if body
      parse!(http_start(uri, req))
    rescue SocketError, Timeout::Error, IOError, EOFError, SystemCallError, OpenSSL::SSL::SSLError => e
      raise Error.new("Ozon unreachable: #{e.message}", kind: :network, detail: e.class.name)
    end

    def get(uri)
      req = Net::HTTP::Get.new(uri)
      req["Accept"] = "application/json"
      http_start(uri, req)
    rescue SocketError, Timeout::Error, IOError, EOFError, SystemCallError, OpenSSL::SSL::SSLError => e
      raise Error.new("Ozon unreachable: #{e.message}", kind: :network, detail: e.class.name)
    end

    def http_start(uri, req)
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 10, read_timeout: 30) do |http|
        http.request(req)
      end
    end

    def parse!(response)
      parsed = begin
        JSON.parse(response.body.presence || "{}")
      rescue JSON::ParserError
        nil
      end
      json = parsed.is_a?(Hash) ? parsed : {}
      status = response.code.to_i
      ok = status.between?(200, 299) && !auth_failure?(status, json, response) && json["success"] != false && json["error"].blank? && json["ERROR"].blank?
      return json if ok

      message = json["message"].presence || json["MESSAGE"].presence || json["error"].presence || json["ERROR"].presence || "HTTP #{status}"
      raise Error.new(message.to_s, status: status, body: json,
        kind: failure_kind(response, parsed, json), detail: failure_detail(response, json))
    end

    def auth_failure?(status, json, response)
      return true if [ 401, 403 ].include?(status) && !cloudflare_block?(response)

      text = [ json["message"], json["MESSAGE"], json["error"], json["ERROR"] ].compact.join(" ").downcase
      text.match?(/invalid|invalide|unauthorized|unauthori[sz]ed|clé|api.?key|identifiant|credential|forbidden|accès refusé|acces refuse/)
    end

    def cloudflare_block?(response)
      response["server"].to_s.casecmp?("cloudflare") && (response["cf-mitigated"].present? || response["content-type"].to_s.include?("html"))
    end

    def failure_kind(response, parsed, json)
      status = response.code.to_i
      return :blocked if cloudflare_block?(response)
      return :invalid_keys if auth_failure?(status, json, response) || [ 401, 422 ].include?(status)
      return :unexpected if parsed.nil? || status >= 500

      :rejected
    end

    def failure_detail(response, json)
      parts = [ "HTTP #{response.code}" ]
      parts << "Cloudflare" if response["server"].to_s.casecmp?("cloudflare")
      title = response.body.to_s[%r{<title>\s*(.*?)\s*</title>}mi, 1]
      parts << "« #{title.squish.first(80)} »" if title.present?
      msg = json["message"] || json["MESSAGE"] || json["error"] || json["ERROR"]
      parts << msg.to_s.squish.first(120) if msg.present?
      parts << "cf-ray #{response['cf-ray']}" if response["cf-ray"].present?
      parts.join(" · ")
    end

    def log_failure(error, endpoint)
      secrets = [ keys[:customer_id], keys[:api_key] ].compact_blank
      line = "[Ozon] store=#{store.slug} endpoint=#{endpoint} kind=#{error.kind.inspect} status=#{error.status.inspect} detail=#{error.detail.inspect} message=#{error.message.to_s.first(200).inspect}"
      secrets.each { |secret| line = line.gsub(secret.to_s, "[FILTERED]") }
      Rails.logger.warn(line)
    end
  end
end
