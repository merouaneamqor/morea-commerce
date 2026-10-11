# frozen_string_literal: true

require "net/http"
require "uri"

module Recolor
  class Error < StandardError; end
  class Unavailable < Error; end

  class Client
    DEFAULT_TIMEOUT = 120

    def initialize(base_url: ENV.fetch("RECOLOR_SERVICE_URL", "http://recolor:8080"))
      @base_url = base_url.to_s.chomp("/")
    end

    def healthy?
      uri = URI("#{ @base_url }/health")
      response = request(uri, method: :get)
      response.is_a?(Net::HTTPSuccess)
    rescue StandardError
      false
    end

    def recolor(image_bytes:, hex_color:, mask_bytes: nil, auto_segment: true)
      uri = URI("#{ @base_url }/recolor")
      fields = {
        "hex_color" => hex_color,
        "auto_segment" => auto_segment ? "true" : "false",
        "exclude_skin" => "true"
      }
      files = [
        [ "image", image_bytes, "image/jpeg", "source.jpg" ]
      ]
      files << [ "mask", mask_bytes, "image/png", "mask.png" ] if mask_bytes.present?

      body, content_type = multipart_body(fields, files)
      response = request(uri, method: :post, body: body, content_type: content_type)
      raise Error, "Recolor failed (#{ response.code }): #{ response.body.to_s.truncate(200) }" unless response.is_a?(Net::HTTPSuccess)

      response.body
    end

    private

    def request(uri, method:, body: nil, content_type: nil)
      http = Net::HTTP.new(uri.host, uri.port)
      http.open_timeout = 10
      http.read_timeout = DEFAULT_TIMEOUT
      http.use_ssl = uri.scheme == "https"

      req =
        case method
        when :get then Net::HTTP::Get.new(uri)
        when :post then Net::HTTP::Post.new(uri)
        else raise ArgumentError, "unsupported method #{ method }"
        end
      req["Content-Type"] = content_type if content_type
      req.body = body if body

      http.request(req)
    rescue Errno::ECONNREFUSED, SocketError => e
      raise Unavailable, "Recolor service unreachable at #{ @base_url }: #{ e.message }"
    end

    def multipart_body(fields, files)
      boundary = "----MoreaRecolor#{ SecureRandom.hex(8) }"
      body = +""
      fields.each do |name, value|
        body << "--#{ boundary }\r\n"
        body << "Content-Disposition: form-data; name=\"#{ name }\"\r\n\r\n"
        body << value.to_s
        body << "\r\n"
      end
      files.each do |field_name, bytes, mime, filename|
        body << "--#{ boundary }\r\n"
        body << "Content-Disposition: form-data; name=\"#{ field_name }\"; filename=\"#{ filename }\"\r\n"
        body << "Content-Type: #{ mime }\r\n\r\n"
        body << bytes
        body << "\r\n"
      end
      body << "--#{ boundary }--\r\n"
      [ body, "multipart/form-data; boundary=#{ boundary }" ]
    end
  end
end
