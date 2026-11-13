# frozen_string_literal: true

require "rails_helper"

RSpec.describe Sendit::Client do
  let(:store) { Store.create!(name: "Client #{SecureRandom.hex(4)}", slug: "client-#{SecureRandom.hex(5)}", currency: "MAD") }
  let(:cloudflare_page) { "<!DOCTYPE html><html><head><title>Attention Required! | Cloudflare</title></head><body>Sorry, you have been blocked</body></html>" }

  def response_double(code, body, headers = {})
    body = body.to_json unless body.is_a?(String)
    double = instance_double(Net::HTTPResponse, code: code.to_s, body: body)
    allow(double).to receive(:[]) { |name| headers[name.to_s.downcase] }
    double
  end

  def stub_login(response)
    allow_any_instance_of(described_class).to receive(:perform).and_return(response)
  end

  def verify(public_key: "pub", secret_key: "sec")
    described_class.verify!(store, public_key: public_key, secret_key: secret_key)
  end

  describe ".verify!" do
    it "logs in with the public and secret keys and returns Sendit's token" do
      requests = []
      allow_any_instance_of(described_class).to receive(:perform) do |_client, method, uri, body, bearer|
        requests << [ method, uri.to_s, body, bearer ]
        response_double(200, { success: true, data: { token: "abc123" } })
      end
      expect(verify).to eq("abc123")
      expect(requests).to eq([ [ :post, "https://app.sendit.ma/api/v1/login", { public_key: "pub", secret_key: "sec" }, nil ] ])
    end

    it "does not use or fill the workspace's cached session" do
      stub_login(response_double(200, { success: true, data: { token: "abc123" } }))
      expect(Rails.cache).not_to receive(:fetch)
      verify
    end

    it "sends JSON in both directions" do
      sent = nil
      allow(Net::HTTP).to receive(:start) do |*_args, &block|
        http = instance_double(Net::HTTP)
        allow(http).to receive(:request) { |request| sent = request; response_double(200, { success: true, data: { token: "t" } }) }
        block.call(http)
      end
      verify
      expect(sent).to be_a(Net::HTTP::Post)
      expect(sent["Content-Type"]).to eq("application/json")
      expect(sent["Accept"]).to eq("application/json")
      expect(JSON.parse(sent.body)).to eq("public_key" => "pub", "secret_key" => "sec")
    end

    describe "tells the failures apart" do
      def failure
        verify
      rescue described_class::Error => error
        error
      end

      it "reports keys refused by Sendit's API (401 and 422)" do
        stub_login(response_double(401, { success: false, message: "Identifiants invalides" }))
        expect(failure).to have_attributes(kind: :invalid_keys, status: 401, message: "Identifiants invalides")
        stub_login(response_double(422, { success: false, message: "The given data was invalid.", errors: { public_key: [ "invalid" ] } }))
        expect(failure).to have_attributes(kind: :invalid_keys, status: 422)
      end

      it "reports Cloudflare's block page as a block, not as bad keys" do
        stub_login(response_double(403, cloudflare_page, "server" => "cloudflare", "content-type" => "text/html; charset=UTF-8", "cf-ray" => "a5485a-LIS"))
        error = failure
        expect(error).to have_attributes(kind: :blocked, status: 403)
        expect(error.detail).to eq("HTTP 403 · Cloudflare · « Attention Required! | Cloudflare » · cf-ray a5485a-LIS")
      end

      it "reports a 403 answered by Sendit's API itself as a refusal with its message" do
        stub_login(response_double(403, { success: false, message: "Compte désactivé" }, "server" => "nginx", "content-type" => "application/json"))
        expect(failure).to have_attributes(kind: :rejected, status: 403)
        expect(failure.detail).to include("HTTP 403", "Compte désactivé")
      end

      it "reports other answers as unexpected: HTML, server errors, and a success without a token" do
        stub_login(response_double(502, "<html><title>Bad gateway</title></html>", "server" => "nginx", "content-type" => "text/html"))
        expect(failure).to have_attributes(kind: :unexpected, status: 502)
        stub_login(response_double(500, { message: "Server Error" }))
        expect(failure).to have_attributes(kind: :unexpected, status: 500)
        stub_login(response_double(200, "<html>maintenance</html>", "content-type" => "text/html"))
        expect(failure).to have_attributes(kind: :unexpected, status: 200, message: /no token/)
        stub_login(response_double(200, { success: true, data: {} }))
        expect(failure).to have_attributes(kind: :unexpected, status: 200)
      end

      it "reports network problems before any answer: DNS, timeout, reset, TLS" do
        [ SocketError.new("getaddrinfo: Name or service not known"), Net::ReadTimeout.new, Net::OpenTimeout.new, Errno::ECONNRESET.new, Errno::EHOSTUNREACH.new,
          EOFError.new, OpenSSL::SSL::SSLError.new("certificate verify failed") ].each do |exception|
          allow(Net::HTTP).to receive(:start).and_raise(exception)
          error = failure
          expect(error).to have_attributes(kind: :network, status: nil, detail: exception.class.name)
        end
      end
    end

    describe "logging" do
      it "logs the kind, status and a safe detail, and never the keys even when Sendit echoes them" do
        stub_login(response_double(422, { success: false, message: "Invalid secret-xyz for pub-abc" }))
        lines = []
        allow(Rails.logger).to receive(:warn) { |line| lines << line }
        expect { verify(public_key: "pub-abc", secret_key: "secret-xyz") }.to raise_error(described_class::Error)
        line = lines.find { |l| l.start_with?("[Sendit login]") }
        expect(line).to include("kind=:invalid_keys", "status=422", "store=#{store.slug}")
        expect(line).not_to include("secret-xyz", "pub-abc")
        expect(line).to include("[FILTERED]")
      end
    end
  end
end
