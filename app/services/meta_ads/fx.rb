# frozen_string_literal: true

require "net/http"
require "json"

module MetaAds
  # Converts an ad account's currency into the store's currency, and says which rate and which day's rate was used.
  # The source publishes the latest rate only, so older days (the 30 day backfill) use the closest rate on record
  # and carry that rate's own date. If no rate can be had, the conversion is left empty and retried on the next
  # sync: an amount is never converted with an invented rate.
  class Fx
    SOURCE = "open.er-api.com"
    URL = "https://open.er-api.com/v6/latest/%<base>s"
    FRESH_FOR = 1.day

    Quote = Struct.new(:rate, :date, keyword_init: true)

    # fetcher: ->(base_currency) { parsed JSON Hash } is for tests; nothing live is called when it is given.
    def initialize(fetcher: nil)
      @fetcher = fetcher
      @attempted = {}
    end

    def self.normalize(code)
      code = code.to_s.strip.upcase
      code == "DH" ? "MAD" : code
    end

    def quote(from, to, on:)
      from = self.class.normalize(from)
      to = self.class.normalize(to)
      return if from.blank? || to.blank?
      return Quote.new(rate: BigDecimal(1), date: on) if from == to

      refresh(from, to)
      rows = ExchangeRate.where(base_currency: from, quote_currency: to).order(rate_date: :desc).limit(90).to_a
      row = rows.find { |candidate| candidate.rate_date <= on } || rows.last
      Quote.new(rate: row.rate, date: row.rate_date) if row
    end

    private

    def refresh(from, to)
      key = [ from, to ]
      return if @attempted[key]

      @attempted[key] = true
      return if ExchangeRate.where(base_currency: from, quote_currency: to, fetched_at: FRESH_FOR.ago..).exists?

      body = fetch(from)
      rate = BigDecimal(body.dig("rates", to).to_s, exception: false) if body.is_a?(Hash) && body["result"] == "success"
      return unless rate&.positive?

      date = Time.at(body["time_last_update_unix"].to_i).utc.to_date
      record = ExchangeRate.find_or_initialize_by(base_currency: from, quote_currency: to, rate_date: date)
      record.update!(rate: rate, source: SOURCE, fetched_at: Time.current)
    rescue JSON::ParserError, ActiveRecord::RecordInvalid, ArgumentError, TypeError
      nil
    end

    def fetch(base)
      return @fetcher.call(base) if @fetcher

      uri = URI(format(URL, base: base))
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10) { |http| http.get(uri.request_uri, "Accept" => "application/json") }
      JSON.parse(response.body) if response.is_a?(Net::HTTPSuccess) && response.body.bytesize < 200_000
    rescue Timeout::Error, IOError, SystemCallError, SocketError, OpenSSL::SSL::SSLError
      nil
    end
  end
end
