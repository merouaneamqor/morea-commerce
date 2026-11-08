# frozen_string_literal: true

module Admin
  # Cached Sendit city lists and rates for the settings page. Never calls the provider.
  module SenditSettingsLoading
    extend ActiveSupport::Concern

    private

    def load_sendit_settings
      @store = current_store
      @sendit_pickup_cities = []
      @sendit_city_rates = {}
      return unless @store.sendit_configured?

      key = Sendit::Districts.cache_key(@store)
      @sendit_pickup_cities = Array(Rails.cache.read("#{key}:pickup")).filter_map do |row|
        next unless row.is_a?(Hash)

        id = (row[:id] || row["id"]).to_i
        name = (row[:name] || row["name"]).to_s
        { id: id, name: name } if id.positive? && name.present?
      end.uniq { |row| row[:id] }.sort_by { |row| row[:name] }
      Array(Rails.cache.read(key)).each do |row|
        next unless row.is_a?(Hash)

        city = (row[:ville] || row["ville"]).to_s.strip
        price = BigDecimal((row[:price] || row["price"]).to_s, exception: false)
        next unless city.present? && price&.finite? && price >= 0

        @sendit_city_rates[city] ||= (price * 100).to_i
      end
    end
  end
end
