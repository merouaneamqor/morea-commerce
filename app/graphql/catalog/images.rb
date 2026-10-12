# frozen_string_literal: true

require "stringio"
require "net/http"
require "resolv"
require "ipaddr"

module Catalog
  module Images
    MAX_BYTES = 8.megabytes
    MAX_PER_CALL = 4
    ALLOWED_TYPES = %w[image/jpeg image/png image/webp image/gif].freeze
    EXTENSIONS = {
      "image/jpeg" => "jpg",
      "image/png" => "png",
      "image/webp" => "webp",
      "image/gif" => "gif"
    }.freeze

    Image = Data.define(:id, :filename, :url, :position)

    class Error < StandardError; end

    module_function

    def present(attachment, store:, position:)
      Image.new(
        id: attachment.id.to_s,
        filename: attachment.filename.to_s,
        url: absolute_url(attachment, store),
        position: position
      )
    end

    def attach_product!(product, uploads)
      files = Array(uploads)
      raise Error, "No images" if files.empty?
      raise Error, "At most #{MAX_PER_CALL} images at a time" if files.size > MAX_PER_CALL

      files.each { |upload| product.images.attach(io_for(upload)) }
      sync_order!(product)
    end

    def remove_product!(product, ids)
      wanted = Array(ids).map(&:to_i).uniq
      raise Error, "No image ids" if wanted.empty?

      attachments = product.images_attachments.where(id: wanted)
      missing = wanted - attachments.map(&:id)
      raise Error, "Unknown image ids: #{missing.join(", ")}" if missing.any?

      attachments.find_each(&:purge)
      sync_order!(product)
    end

    def reorder_product!(product, ids)
      current = product.images_attachments.pluck(:id)
      wanted = Array(ids).map(&:to_i)
      unknown = wanted - current
      raise Error, "Unknown image ids: #{unknown.join(", ")}" if unknown.any?

      product.update_column(:image_order, wanted + (current - wanted))
    end

    def attach_collection!(collection, upload)
      collection.image.purge if collection.image.attached?
      collection.image.attach(io_for(upload))
    end

    def remove_collection!(collection)
      raise Error, "Collection has no image" unless collection.image.attached?

      collection.image.purge
    end

    def sync_order!(product)
      ids = product.images_attachments.reload.order(:id).ids
      order = Array(product.image_order) & ids
      product.update_column(:image_order, order + (ids - order))
    end

    def absolute_url(attachment, store)
      url = MediaUrl.for(attachment, store: store)
      url = "#{store.origin}#{url}" unless url.to_s.start_with?("http://", "https://")
      MediaUrl.delivery(url, width: 1200)
    end

    def jpeg_bytes(url, width: 480)
      uri = URI.parse(MediaUrl.delivery(url, width: width))
      return unless uri.is_a?(URI::HTTPS) && uri.host == "res.cloudinary.com"

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 3
      http.read_timeout = 8
      response = http.request(Net::HTTP::Get.new(uri))
      return unless response.is_a?(Net::HTTPSuccess)
      return if response.body.bytesize > 300_000
      return unless response["content-type"].to_s.include?("image/jpeg")

      response.body
    rescue StandardError
      nil
    end

    def io_for(upload)
      attrs = upload.to_h.symbolize_keys
      if attrs[:base64].present?
        decode_base64(attrs)
      elsif attrs[:url].present?
        download(attrs[:url], attrs[:filename])
      else
        raise Error, "Each image needs base64 or url"
      end
    end

    def decode_base64(attrs)
      raw = attrs[:base64].to_s
      content_type = attrs[:content_type].presence
      if raw.start_with?("data:")
        header, raw = raw.split(",", 2)
        content_type ||= header[/data:([^;]+)/, 1]
      end
      content_type = normalize_type(content_type)
      bytes = Base64.decode64(raw.to_s)
      build_io(bytes, content_type, attrs[:filename])
    end

    def download(url, filename)
      uri = parse_http(url)
      body, content_type = fetch(uri, redirects: 3)
      build_io(body, content_type, filename.presence || filename_from(uri))
    end

    def build_io(bytes, content_type, filename)
      raise Error, "Unsupported image type" unless ALLOWED_TYPES.include?(content_type)
      raise Error, "Image is empty" if bytes.bytesize.zero?
      raise Error, "Image is larger than 8MB" if bytes.bytesize > MAX_BYTES

      name = filename.presence || "image.#{EXTENSIONS.fetch(content_type)}"
      { io: StringIO.new(bytes), filename: name, content_type: content_type }
    end

    def fetch(uri, redirects:)
      raise Error, "Too many redirects" if redirects.negative?

      assert_public_host!(uri.host)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 5
      http.read_timeout = 15
      request = Net::HTTP::Get.new(uri)
      request["User-Agent"] = "MoreaCatalog/1.0"

      http.request(request) do |response|
        if response.is_a?(Net::HTTPRedirection)
          location = URI.join(uri, response["location"].to_s)
          return fetch(location, redirects: redirects - 1)
        end
        raise Error, "Could not download image (#{response.code})" unless response.is_a?(Net::HTTPSuccess)

        content_type = normalize_type(response["content-type"])
        raise Error, "URL is not an image" unless ALLOWED_TYPES.include?(content_type)

        body = +""
        response.read_body do |chunk|
          body << chunk
          raise Error, "Image is larger than 8MB" if body.bytesize > MAX_BYTES
        end
        return [ body, content_type ]
      end
    end

    def parse_http(url)
      uri = URI.parse(url.to_s)
      raise Error, "Image URL must be http or https" unless uri.is_a?(URI::HTTP) && uri.host.present?

      uri
    rescue URI::InvalidURIError
      raise Error, "Image URL is invalid"
    end

    def assert_public_host!(host)
      addresses = Resolv.getaddresses(host.to_s)
      raise Error, "Could not resolve image URL" if addresses.empty?

      addresses.each do |ip|
        addr = IPAddr.new(ip)
        raise Error, "Image URL host is not allowed" if addr.loopback? || addr.private? || addr.link_local?
      end
    end

    def normalize_type(value)
      value.to_s.split(";").first.to_s.strip.downcase
    end

    def filename_from(uri)
      name = File.basename(uri.path.to_s)
      name.presence unless name == "/" || name.include?("\0")
    end
  end
end
