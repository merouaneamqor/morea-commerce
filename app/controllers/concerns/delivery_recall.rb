# frozen_string_literal: true

module DeliveryRecall
  extend ActiveSupport::Concern

  private

  def remember_delivery_from_checkout!(checkout)
    session[:last_delivery] = {
      "name" => checkout.name.to_s.strip,
      "phone" => checkout.phone.to_s.strip,
      "phone_country" => checkout.phone_country.to_s.presence || "MA",
      "city" => checkout.city.to_s.strip,
      "district" => checkout.district.to_s.strip,
      "address" => checkout.address.to_s.strip
    }
  end

  def delivery_recall_attributes(overrides = {})
    base = session[:last_delivery].to_h.stringify_keys
    overrides.stringify_keys.each { |key, value| base[key] = value if value.present? }
    base.slice("name", "phone", "phone_country", "city", "district", "address", "discount_code")
  end
end
