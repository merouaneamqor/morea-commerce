# frozen_string_literal: true

require "net/http"
require "json"
require "base64"
require "securerandom"

module Recolor
  # Posts the original photo to the OpenCV service and returns PNG bytes.
  class Client
    Result = Struct.new(:image, :mask, :report, keyword_init: true)

    def self.recolor(...) = new.recolor(...)

    def recolor(image_bytes:, filename:, content_type:, hex:, prompt: nil, points: nil)
      uri = URI.parse("#{base_url}/v1/recolor")
      boundary = "recolor#{SecureRandom.hex(12)}"
      body = multipart(boundary, hex:, prompt:, points:, image_bytes:, filename:, content_type:)
      response = post(uri, body, boundary)
      payload = parse(response)
      raise Error, payload["error"].presence || "Recolor failed." unless response.is_a?(Net::HTTPSuccess)

      Result.new(
        image: Base64.strict_decode64(payload.fetch("image_png_base64")),
        mask: Base64.strict_decode64(payload.fetch("mask_png_base64")),
        report: payload.fetch("report", {})
      )
    rescue KeyError, ArgumentError
      raise Error, "The recolor service returned an unexpected response."
    end

    private

    def base_url
      ENV.fetch("RECOLOR_SERVICE_URL", "http://127.0.0.1:8000").chomp("/")
    end

    def post(uri, body, boundary)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 3
      http.read_timeout = Integer(ENV.fetch("RECOLOR_TIMEOUT", 45))
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "multipart/form-data; boundary=#{boundary}"
      request["Accept"] = "application/json"
      request.body = body
      http.request(request)
    rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, SocketError, Net::OpenTimeout, Net::ReadTimeout
      raise Error, "The recolor service is not running. Start it with docker compose, then try again."
    end

    def parse(response)
      JSON.parse(response.body.to_s)
    rescue JSON::ParserError
      {}
    end

    def multipart(boundary, hex:, prompt:, points:, image_bytes:, filename:, content_type:)
      safe_name = filename.to_s.gsub(/[^\w.\-]+/, "_").presence || "product.jpg"
      body = +"".b
      field(body, boundary, "color", hex)
      field(body, boundary, "prompt", prompt.to_s)
      field(body, boundary, "points", Array(points).to_json)
      body << "--#{boundary}\r\n".b
      body << "Content-Disposition: form-data; name=\"image\"; filename=\"#{safe_name}\"\r\n".b
      body << "Content-Type: #{content_type.presence || "application/octet-stream"}\r\n\r\n".b
      body << image_bytes.b
      body << "\r\n--#{boundary}--\r\n".b
      body
    end

    def field(body, boundary, name, value)
      body << "--#{boundary}\r\n".b
      body << "Content-Disposition: form-data; name=\"#{name}\"\r\n\r\n".b
      body << value.to_s.b
      body << "\r\n".b
    end
  end
end
