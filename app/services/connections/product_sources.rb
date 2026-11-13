# frozen_string_literal: true

require "net/http"
require "json"
require "ipaddr"

module Connections
  # Where the catalog of a connected store is read from: one source per platform, each turning the platform's own
  # products into the same two shapes (Item and Variant), which ProductImport then writes. A source only reads.
  module ProductSources
    CODES = %w[credentials_missing invalid_credentials missing_scopes disconnected rate_limited unavailable invalid_response unsafe_domain].freeze

    class Error < StandardError
      attr_reader :code

      def initialize(code)
        @code = CODES.include?(code) ? code : "unavailable"
        super("Product source: #{@code}")
      end
    end

    # price_cents / compare_at_cents are whole centimes (nil when the platform gave none); stock is nil when the
    # platform does not track it; options is a list of [name, value].
    Variant = Data.define(:external_id, :name, :sku, :price_cents, :stock, :options, :active)
    Item = Data.define(:external_id, :name, :status, :price_cents, :compare_at_cents, :sku, :image_url, :track_inventory, :stock, :variants)

    def self.for(connection, transport: nil)
      case connection.provider
      when "shopify" then Shopify.new(connection: connection, transport: transport)
      when "woocommerce" then Woocommerce.new(connection: connection, transport: transport)
      when "youcan" then Youcan.new(connection: connection, transport: transport)
      else raise Error.new("unavailable")
      end
    end

    # "12.50" -> 1250, 12 -> 1200, nil or "" -> nil. Never a float.
    def self.cents(value)
      return if value.nil? || value.to_s.strip.empty?

      (BigDecimal(value.to_s) * 100).round(0).to_i
    rescue ArgumentError, TypeError
      nil
    end

    # A shop address is only ever fetched when it is a public host name: no IP address, no local or internal name.
    def self.public_host?(host)
      host = host.to_s.downcase
      return false unless host.include?(".") && host.match?(/\A[a-z0-9.-]+\z/) && host.bytesize <= 253
      return false if host.end_with?(".local", ".internal", ".localhost", ".lan", ".home")

      IPAddr.new(host)
      false
    rescue IPAddr::InvalidAddressError
      true
    end

    # One JSON GET. `transport` (tests) answers like Net::HTTP: #code, #body and #[] for a header.
    module Http
      OPEN_TIMEOUT = 5
      READ_TIMEOUT = 25
      MAX_BODY = 8.megabytes

      module_function

      def get_json(uri, headers: {}, basic_auth: nil, transport: nil)
        request = Net::HTTP::Get.new(uri)
        headers.each { |name, value| request[name] = value }
        request.basic_auth(*basic_auth) if basic_auth
        response = transport ? transport.call(uri, request) : perform(uri, request)
        status = response.code.to_i
        raise Error.new("invalid_credentials") if [ 401, 403 ].include?(status)
        raise Error.new("rate_limited") if status == 429
        raise Error.new("unavailable") unless status.between?(200, 299)
        raise Error.new("invalid_response") if response.body.to_s.bytesize > MAX_BODY

        [ JSON.parse(response.body.to_s), response ]
      rescue JSON::ParserError
        raise Error.new("invalid_response")
      end

      def perform(uri, request)
        Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) { |http| http.request(request) }
      rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError, OpenSSL::SSL::SSLError
        raise Error.new("unavailable")
      end
    end
  end
end
