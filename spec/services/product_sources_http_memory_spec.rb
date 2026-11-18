# frozen_string_literal: true

require "rails_helper"
require "socket"

RSpec.describe Connections::ProductSources::Http do
  let(:uri) { URI("https://synthetic.example.test/products") }
  let(:http) { instance_double(Net::HTTP) }
  let(:response) { Net::HTTPOK.new("1.1", "200", "OK") }

  before do
    allow(Net::HTTP).to receive(:start).with(uri.host, uri.port,
      use_ssl: true, open_timeout: described_class::OPEN_TIMEOUT, read_timeout: described_class::READ_TIMEOUT).and_yield(http)
    allow(http).to receive(:request) do |_request, &block|
      raise "Response must be streamed" unless block

      block.call(response)
      response
    end
  end

  def stream(*chunks)
    allow(response).to receive(:read_body).and_wrap_original do |original, &block|
      if block
        chunks.each { |chunk| block.call(chunk) }
        response.instance_variable_set(:@read, true)
      else
        original.call
      end
    end
  end

  def expect_code(code, &block)
    expect(&block).to raise_error(Connections::ProductSources::Error) { |error| expect(error.code).to eq(code) }
  end

  it "parses streamed JSON and preserves response headers used for pagination" do
    response["X-WP-TotalPages"] = "3"
    stream('[{"id":', '42}]')

    data, metadata = described_class.get_json(uri)

    expect(data).to eq([ { "id" => 42 } ])
    expect(metadata["X-WP-TotalPages"]).to eq("3")
    expect(metadata.body).to eq('[{"id":42}]')
  end

  it "keeps the Net::HTTP response readable after consuming a real chunked response" do
    server = TCPServer.new("127.0.0.1", 0)
    port = server.addr[1]
    worker = Thread.new do
      socket = server.accept
      loop { break if socket.gets == "\r\n" }
      socket.write("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nX-WP-TotalPages: 2\r\nConnection: close\r\n\r\n")
      [ '[{"id":', '42}]' ].each { |chunk| socket.write("#{chunk.bytesize.to_s(16)}\r\n#{chunk}\r\n") }
      socket.write("0\r\n\r\n")
      socket.close
    end
    allow(Net::HTTP).to receive(:start).and_wrap_original do |original, _host, _port, **options, &block|
      original.call("127.0.0.1", port, **options.merge(use_ssl: false), &block)
    end

    data, metadata = described_class.get_json(uri)

    expect(data).to eq([ { "id" => 42 } ])
    expect(metadata.body).to eq('[{"id":42}]')
    expect(metadata["X-WP-TotalPages"]).to eq("2")
  ensure
    worker&.kill
    worker&.join
    server&.close
  end

  it "stops consuming an unknown-length response as soon as the byte limit is exceeded" do
    stub_const("Connections::ProductSources::Http::MAX_BODY", 8)
    consumed = 0
    allow(response).to receive(:read_body) do |&block|
      100.times do
        consumed += 1
        block.call("éé")
      end
    end

    expect_code("invalid_response") { described_class.get_json(uri) }
    expect(consumed).to eq(3)
  end

  it "accepts valid JSON exactly at the byte limit" do
    stub_const("Connections::ProductSources::Http::MAX_BODY", 8)
    stream("[", "      ", "]")

    expect(described_class.get_json(uri).first).to eq([])
  end

  it "classifies rejected statuses before reading their possibly large error bodies" do
    { "401" => "invalid_credentials", "403" => "invalid_credentials", "429" => "rate_limited", "500" => "unavailable", "302" => "unavailable" }.each do |status, expected|
      allow(response).to receive(:code).and_return(status)
      expect(response).not_to receive(:read_body)
      expect_code(expected) { described_class.get_json(uri) }
    end
  end

  it "keeps the injected transport contract and request authentication" do
    transport_response = Struct.new(:code, :body).new("200", "[]")
    transport = lambda do |requested_uri, request|
      expect(requested_uri).to eq(uri)
      expect(request["Accept"]).to eq("application/json")
      expect(request["Authorization"]).to eq("Basic #{Base64.strict_encode64('synthetic:fixture')}")
      transport_response
    end
    expect(Net::HTTP).not_to receive(:start)

    data, metadata = described_class.get_json(uri, headers: { "Accept" => "application/json" }, basic_auth: %w[synthetic fixture], transport: transport)

    expect(data).to eq([])
    expect(metadata).to equal(transport_response)
  end

  it "still rejects oversized injected bodies and malformed streamed JSON" do
    stub_const("Connections::ProductSources::Http::MAX_BODY", 8)
    transport = ->(*) { Struct.new(:code, :body).new("200", "x" * 9) }
    expect_code("invalid_response") { described_class.get_json(uri, transport: transport) }
    stream("invalid")
    expect_code("invalid_response") { described_class.get_json(uri) }
  end

  it "maps network failures to an unavailable source" do
    allow(Net::HTTP).to receive(:start).and_raise(Net::ReadTimeout)

    expect_code("unavailable") { described_class.get_json(uri) }
  end
end
