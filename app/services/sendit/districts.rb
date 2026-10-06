# frozen_string_literal: true

module Sendit
  # Sendit destination districts ("Casablanca - Ain sebaa", "Rabat"…), cached for a day,
  # and matched against the free-text city/address customers type at checkout.
  # Each district includes Sendit's delivery `price` (MAD) used for checkout shipping.
  class Districts
    CACHE_KEY = "sendit:districts:v2"

    def self.all(client: Client.new)
      Rails.cache.fetch(CACHE_KEY, expires_in: 1.day) do
        rows = []
        page = 1
        loop do
          response = client.districts(page: page)
          rows.concat(Array(response["data"]).map { |d|
            {
              id: d["id"].to_i,
              ville: d["ville"].to_s,
              name: d["name"].to_s,
              price: d["price"].to_s
            }
          })
          break if page >= response["last_page"].to_i || page >= 20

          page += 1
        end
        rows
      end
    end

    def self.pickup_cities(client: Client.new)
      Rails.cache.fetch("#{CACHE_KEY}:pickup", expires_in: 1.day) do
        client.pickup_cities.map { |d| { id: d["id"].to_i, name: d["name"].to_s } }.sort_by { |d| d[:name] }
      end
    end

    def self.find(id)
      all.find { |d| d[:id] == id.to_i }
    end

    # MAD amount → cents. Prefer an exact district match, else the city's tariff.
    def self.shipping_cents_for(city:, district: nil, address: "")
      return unless Client.configured?
      return if city.blank?

      # Same address priority as Checkout#sendit_district (quartier wins over free-text)
      match = self.match(city: city, address: district.presence || address.to_s)
      price = match&.dig(:price).presence || price_for_city(city)
      return if price.blank?

      (price.to_d * 100).to_i
    rescue StandardError => e
      Rails.logger.warn("[Sendit::Districts] shipping lookup failed: #{e.message}")
      nil
    end

    # { "Casablanca" => 1900, "Rabat" => 3500, … } for the checkout form
    def self.shipping_cents_by_city
      return {} unless Client.configured?

      all.each_with_object({}) do |d, map|
        next if d[:ville].blank? || d[:price].blank?

        map[d[:ville]] ||= (d[:price].to_d * 100).to_i
      end
    rescue StandardError => e
      Rails.logger.warn("[Sendit::Districts] city rates unavailable: #{e.message}")
      {}
    end

    def self.price_for_city(city)
      city_n = I18n.transliterate(city.to_s).downcase.gsub(/[^a-z0-9]+/, " ").squish
      row = all.find { |d|
        I18n.transliterate(d[:ville].to_s).downcase.gsub(/[^a-z0-9]+/, " ").squish == city_n
      }
      row&.dig(:price)
    end

    # Best district for a city + address, or nil when it can't be decided safely
    def self.match(city:, address: "", districts: all)
      new(districts).match(city, address)
    end

    # Districts of the city the customer typed (typo-tolerant), for the admin picker
    def self.candidates(city:, districts: all)
      new(districts).candidates(city)
    end

    def initialize(districts)
      @districts = districts
    end

    def match(city, address)
      city_n = normalize(city)
      text = " #{normalize("#{address} #{city}")} "
      pool = candidates(city)
      # Customer typed a neighbourhood as the city ("Ain Sebaa")
      pool = @districts.select { |d| text.include?(" #{normalize(area(d))} ") } if pool.empty?
      return if pool.empty?

      by_area = pool.select { |d| area(d).present? && text.include?(" #{normalize(area(d))} ") }
      return by_area.max_by { |d| area(d).length } if by_area.any?

      pool.find { |d| normalize(d[:name]) == city_n || normalize(d[:name]) == normalize(d[:ville]) } ||
        (pool.first if pool.size == 1)
    end

    def candidates(city)
      city_n = normalize(city)
      return [] if city_n.blank?

      exact = @districts.select { |d| normalize(d[:ville]) == city_n || normalize(d[:name]) == city_n }
      return exact if exact.any?

      @districts.select do |d|
        ville = normalize(d[:ville])
        ville.length > 3 && DidYouMean::Levenshtein.distance(ville, city_n) <= (ville.length > 6 ? 2 : 1)
      end
    end

    private

    # "Casablanca - Ain sebaa" -> "Ain sebaa"
    def area(district)
      district[:name].to_s.split(" - ", 2)[1].to_s
    end

    def normalize(value)
      I18n.transliterate(value.to_s).downcase.gsub(/[^a-z0-9]+/, " ").squish
    end
  end
end
