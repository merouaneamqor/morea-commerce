require "net/http"
require "json"

module Whatsapp
  # The WhatsApp Business Cloud API of Meta, for one account. Only the fixed Meta host is called. `transport:` (->(uri, request) { response }) is for tests:
  # nothing live is called when it is given. A free-text message only reaches a customer who wrote to the business in the last 24 hours; to start a
  # conversation Meta requires an approved template (not built yet).
  class CloudApi
    class Error < StandardError; end

    HOST = "graph.facebook.com".freeze

    def initialize(account:, transport: nil)
      @account, @transport = account, transport
    end

    # Sends a text message and returns the id Meta gave it. `to` is the number in international format, digits only.
    def send_text(to:, body:)
      uri = URI("https://#{HOST}/#{@account.api_version}/#{@account.phone_number_id}/messages")
      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{@account.access_token}"
      request["Content-Type"] = "application/json"
      request.body = { messaging_product: "whatsapp", recipient_type: "individual", to: to.to_s.delete("^0-9"), type: "text", text: { preview_url: false, body: body } }.to_json
      response = perform(uri, request)
      data = JSON.parse(response.body.to_s.presence || "{}")
      raise Error, data.dig("error", "message").presence || "WhatsApp answered HTTP #{response.code}" unless response.code.to_i.between?(200, 299)

      data.dig("messages", 0, "id") || raise(Error, "WhatsApp did not return a message id")
    rescue JSON::ParserError
      raise Error, "WhatsApp answered with something unreadable (HTTP #{response&.code})"
    end

    private

    def perform(uri, request)
      return @transport.call(uri, request) if @transport

      Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10) { |http| http.request(request) }
    rescue Timeout::Error, SocketError, SystemCallError, OpenSSL::SSL::SSLError => e
      raise Error, "WhatsApp could not be reached (#{e.class.name.demodulize})"
    end
  end
end
