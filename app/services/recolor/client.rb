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
      ensure_local_service!
      uri = URI.parse("#{base_url}/v1/recolor")
      boundary = "recolor#{SecureRandom.hex(12)}"
      body = multipart(boundary, hex:, prompt:, points:, image_bytes:, filename:, content_type:)
      response = post(uri, body, boundary)
      payload = parse(response)
      if response.code.to_i.in?([ 502, 503, 504 ])
        raise Error, "The recolor service is waking up. Wait a minute and try again."
      end
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
      raw = ENV["RECOLOR_SERVICE_URL"].to_s.strip.chomp("/")
      return "http://127.0.0.1:8000" if raw.blank?
      return raw if raw.match?(%r{\Ahttps?://}i)
      # host:port is the Render private-network address. A bare hostname is public.
      return "http://#{raw}" if raw.match?(/:\d+\z/)

      "https://#{raw}"
    end

    def post(uri, body, boundary)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 10
      http.read_timeout = Integer(ENV.fetch("RECOLOR_TIMEOUT", Rails.env.production? ? "120" : "45"))
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "multipart/form-data; boundary=#{boundary}"
      request["Accept"] = "application/json"
      request["Authorization"] = "Bearer #{ENV['RECOLOR_TOKEN']}" if ENV["RECOLOR_TOKEN"].present?
      request.body = body
      http.request(request)
    rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, SocketError, Net::OpenTimeout, Net::ReadTimeout
      raise Error, unavailable_message
    end

    # Git deploys do not apply Render blueprint env vars. When RECOLOR_SERVICE_URL
    # is unset in production, start the OpenCV app installed by bin/render-build.sh.
    def ensure_local_service!
      return unless local_service?

      File.open(lock_path, File::RDWR | File::CREAT, 0o644) do |lock|
        lock.flock(File::LOCK_EX)
        return if local_healthy?

        Rails.logger.info("Starting the local recolor service")
        spawn_local_service!
        wait_until_local_healthy!
      end
    end

    def local_service?
      Rails.env.production? && ENV["RECOLOR_SERVICE_URL"].blank?
    end

    def spawn_local_service!
      python = Rails.root.join(".venv/bin/python")
      raise Error, "The recolor runtime is missing on this server." unless python.file? && python.executable?

      pid = Process.spawn(
        local_service_env,
        python.to_s, "-m", "uvicorn", "app.main:app",
        "--app-dir", Rails.root.join("services/recolor").to_s,
        "--host", "127.0.0.1",
        "--port", "8000",
        "--log-level", "warning",
        local_service_options
      )
      Process.detach(pid)
      File.write(pid_path, pid.to_s)
    rescue Errno::ENOENT, ArgumentError
      raise Error, "The recolor runtime is missing on this server."
    end

    def local_service_env
      ENV.to_h.merge(
        "RECOLOR_MAX_EDGE" => ENV.fetch("RECOLOR_MAX_EDGE", "1000"),
        "OMP_NUM_THREADS" => "1",
        "OPENBLAS_NUM_THREADS" => "1",
        "MKL_NUM_THREADS" => "1"
      )
    end

    def local_service_options
      {
        chdir: Rails.root.to_s,
        out: [ Rails.root.join("log/recolor.log").to_s, "a" ],
        err: [ :child, :out ],
        pgroup: true
      }
    end

    def wait_until_local_healthy!
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 45
      until local_healthy?
        unless local_process_alive?
          raise Error, "The recolor service failed to start. Try again in a minute."
        end
        if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
          raise Error, "The recolor service failed to start. Try again in a minute."
        end

        sleep 0.4
      end
    end

    def local_healthy?
      uri = URI("http://127.0.0.1:8000/health")
      http = Net::HTTP.new(uri.host, uri.port)
      http.open_timeout = 1
      http.read_timeout = 1
      http.get(uri.request_uri).is_a?(Net::HTTPSuccess)
    rescue StandardError
      false
    end

    def local_process_alive?
      pid = Integer(File.read(pid_path))
      Process.kill(0, pid)
      true
    rescue Errno::ENOENT, Errno::ESRCH, ArgumentError
      false
    end

    def lock_path
      Rails.root.join("tmp/pids/recolor.lock")
    end

    def pid_path
      Rails.root.join("tmp/pids/recolor.pid")
    end

    def unavailable_message
      return "The recolor service is not running. Start it with docker compose, then try again." unless Rails.env.production?
      return "The recolor service failed to start. Try again in a minute." if ENV["RECOLOR_SERVICE_URL"].blank?

      "The recolor service did not respond. On Render it can take a minute to wake up. Try again."
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
