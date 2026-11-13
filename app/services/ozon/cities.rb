# frozen_string_literal: true

require "net/http"
require "json"

module Ozon
  # Ozon destination cities from GET /cities, cached for a day and matched to free-text checkout cities.
  class Cities
    def self.cache_key(_store = nil)
      "ozon:cities:v1"
    end

    def self.all(store: nil, client: nil)
      Rails.cache.fetch(cache_key, expires_in: 1.day) do
        fetch(store: store, client: client)
      end
    end

    def self.refresh!(store: nil, client: nil)
      Rails.cache.delete(cache_key)
      all(store: store, client: client).size
    end

    def self.find(id, store: nil)
      all(store: store).find { |c| c[:id] == id.to_i }
    end

    def self.shipping_cents_for(store:, city:)
      return unless Client.configured?(store)
      return if city.blank?

      match = self.match(store: store, city: city)
      return if match.blank? || match[:delivered_price].blank?

      (match[:delivered_price].to_d * 100).to_i
    rescue StandardError => e
      Rails.logger.warn("[Ozon::Cities] shipping lookup failed: #{e.message}")
      nil
    end

    def self.shipping_cents_by_city(store:)
      return {} unless Client.configured?(store)

      all(store: store).each_with_object({}) do |c, map|
        next if c[:name].blank? || c[:delivered_price].blank?

        map[c[:name]] ||= (c[:delivered_price].to_d * 100).to_i
      end
    rescue StandardError => e
      Rails.logger.warn("[Ozon::Cities] city rates unavailable: #{e.message}")
      {}
    end

    def self.match(store:, city:, cities: nil)
      cities ||= all(store: store)
      new(cities).match(city)
    end

    def self.candidates(city:, cities:)
      new(cities).candidates(city)
    end

    def self.fetch(store: nil, client: nil)
      raw = if client
        client.cities
      elsif store && Client.configured?(store)
        Client.new(store).cities
      else
        public_cities
      end

      rows = raw["CITIES"] || raw["cities"] || raw
      rows = rows.values if rows.is_a?(Hash)
      Array(rows).filter_map do |row|
        next unless row.is_a?(Hash)

        id = (row["ID"] || row["id"]).to_i
        name = (row["NAME"] || row["name"]).to_s
        next if id.zero? || name.blank?

        {
          id: id,
          ref: (row["REF"] || row["ref"]).to_s,
          name: name,
          delivered_price: row["DELIVERED-PRICE"] || row["delivered_price"],
          returned_price: row["RETURNED-PRICE"] || row["returned_price"],
          refused_price: row["REFUSED-PRICE"] || row["refused_price"]
        }
      end.sort_by { |c| c[:name] }
    end
    private_class_method :fetch

    def self.public_cities
      uri = URI(ENV.fetch("OZON_CITIES_URL", "https://api.ozonexpress.ma/cities"))
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 10, read_timeout: 30) do |http|
        req = Net::HTTP::Get.new(uri)
        req["Accept"] = "application/json"
        http.request(req)
      end
      raise Client::Error.new("Ozon cities HTTP #{response.code}", status: response.code.to_i, kind: :unexpected) unless response.code.to_i.between?(200, 299)

      JSON.parse(response.body.presence || "{}")
    rescue JSON::ParserError
      raise Client::Error.new("Ozon cities returned non-JSON", kind: :unexpected)
    rescue SocketError, Timeout::Error, IOError, EOFError, SystemCallError, OpenSSL::SSL::SSLError => e
      raise Client::Error.new("Ozon unreachable: #{e.message}", kind: :network, detail: e.class.name)
    end
    private_class_method :public_cities

    def initialize(cities)
      @cities = cities
    end

    def match(city)
      pool = candidates(city)
      return if pool.empty?

      city_n = normalize(city)
      pool.find { |c| normalize(c[:name]) == city_n } || (pool.first if pool.size == 1)
    end

    def candidates(city)
      city_n = normalize(city)
      return [] if city_n.blank?

      exact = @cities.select { |c| normalize(c[:name]) == city_n }
      return exact if exact.any?

      @cities.select do |c|
        name = normalize(c[:name])
        name.length > 3 && DidYouMean::Levenshtein.distance(name, city_n) <= (name.length > 6 ? 2 : 1)
      end
    end

    private

    def normalize(value)
      I18n.transliterate(value.to_s).downcase.gsub(/[^a-z0-9]+/, " ").squish
    end
  end
end
