# frozen_string_literal: true

module Ameex
  # Destination cities from GET /Delivery/Cities, cached per store for a day.
  class Cities
    def self.cache_key(store)
      "ameex:cities:v1:store:#{store.id}"
    end

    def self.all(store:, client: nil)
      raise ArgumentError, "Store is required" unless store

      client ||= Client.new(store)
      Rails.cache.fetch(cache_key(store), expires_in: 1.day) do
        parse(client.cities)
      end
    end

    def self.refresh!(store:, client: nil)
      raise ArgumentError, "Store is required" unless store

      Rails.cache.delete(cache_key(store))
      all(store: store, client: client).size
    end

    def self.find(id, store:)
      all(store: store).find { |c| c[:id] == id.to_i }
    end

    def self.match(store:, city:, cities: nil)
      cities ||= all(store: store)
      new(cities).match(city)
    end

    def self.candidates(city:, cities:)
      new(cities).candidates(city)
    end

    def self.parse(raw)
      rows = raw["data"] || raw["cities"] || raw["CITIES"] || raw
      rows = rows.values if rows.is_a?(Hash) && !rows.key?("id") && !rows.key?("ID")
      Array(rows).filter_map do |row|
        next unless row.is_a?(Hash)

        id = (row["id"] || row["ID"] || row["city_id"] || row["cityId"]).to_i
        name = (row["name"] || row["NAME"] || row["city"] || row["ville"] || row["label"]).to_s
        next if id.zero? || name.blank?

        { id: id, name: name, ref: (row["ref"] || row["REF"] || row["code"]).to_s }
      end.sort_by { |c| c[:name] }
    end
    private_class_method :parse

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
