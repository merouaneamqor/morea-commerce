# frozen_string_literal: true

class Checkout
  include ActiveModel::Model

  attr_accessor :name, :phone, :city, :district, :address, :notes, :cart, :store

  validate :required_fields
  validate :phone_must_be_moroccan
  validate :cart_must_have_items

  # "06 12 34 56 78", "00212612345678", "+212 6…" -> "+212612345678"; nil unless a valid Moroccan number
  def self.normalize_phone(value)
    phone = Phonelib.parse(value, "MA")
    phone.e164 if phone.valid_for_country?("MA")
  end

  # Sendit cities for the checkout dropdown, empty when Sendit isn't reachable
  def self.cities
    return [] unless Sendit::Client.configured?

    Sendit::Districts.all.map { |d| d[:ville] }.compact_blank.uniq.sort
  rescue StandardError => e
    Rails.logger.warn("[Checkout] Sendit cities unavailable: #{e.message}")
    []
  end

  # { "Casablanca" => ["Ain sebaa", "Maarif", …] } to suggest a quartier once the city is picked
  def self.districts_by_city
    return {} unless Sendit::Client.configured?

    Sendit::Districts.all.each_with_object(Hash.new { |h, k| h[k] = [] }) do |d, map|
      area = d[:name].to_s.split(" - ", 2)[1]
      map[d[:ville]] << area if area.present?
    end.transform_values { |areas| areas.uniq.sort }
  rescue StandardError
    {}
  end

  def place_order!
    validate!
    order = nil
    phone_number = self.class.normalize_phone(phone)

    ActiveRecord::Base.transaction do
      customer = Customer.find_or_create_from_checkout!(
        store: store,
        name: name,
        phone: phone_number,
        city: city,
        district: district,
        address: address
      )

      order = store.orders.create!(
        customer: customer,
        customer_name: name,
        customer_phone: phone_number,
        customer_city: city,
        customer_district: district.presence,
        customer_address: address,
        notes: notes,
        payment_method: "cod",
        status: "new",
        currency: store.currency,
        subtotal_cents: cart.subtotal_cents,
        shipping_cents: 0,
        total_cents: cart.subtotal_cents,
        **sendit_district
      )

      cart.cart_items.includes(:product, :product_variant).each do |item|
        order.order_items.create!(
          product: item.product,
          product_variant: item.product_variant,
          product_name: item.product.name,
          variant_name: item.product_variant&.display_name,
          quantity: item.quantity,
          unit_price_cents: item.unit_price_cents,
          total_cents: item.line_total_cents
        )
      end

      customer.increment!(:orders_count)
      cart.cart_items.destroy_all
    end

    OrderStatusJob.perform_later(order.id)
    DiscordOrderNotifyJob.perform_later(order.id)
    order
  end

  private

  # Pin the Sendit district now, so the parcel doesn't need a manual city pick later
  def sendit_district
    return {} unless Sendit::Client.configured?

    match = Sendit::Districts.match(city: city, address: "#{district} #{address}")
    match ? { sendit_district_id: match[:id], sendit_district_name: match[:name] } : {}
  rescue StandardError => e
    Rails.logger.warn("[Checkout] Sendit district match failed: #{e.message}")
    {}
  end

  def required_fields
    %i[name phone city address].each do |field|
      errors.add(field, :blank, message: I18n.t("checkout.errors.#{field}")) if public_send(field).blank?
    end
  end

  def phone_must_be_moroccan
    return if phone.blank? || self.class.normalize_phone(phone)

    errors.add(:phone, :invalid, message: I18n.t("checkout.errors.phone_format"))
  end

  def cart_must_have_items
    errors.add(:base, I18n.t("checkout.errors.empty_cart")) if cart.nil? || cart.empty?
  end
end
