# frozen_string_literal: true

class Checkout
  include ActiveModel::Model

  attr_accessor :name, :phone, :city, :district, :address, :notes, :discount_code, :cart, :store

  validate :required_fields
  validate :phone_must_be_moroccan
  validate :cart_must_have_items
  validate :discount_must_be_valid
  validate :district_must_be_valid

  def subtotal_cents
    cart&.subtotal_cents.to_i
  end

  def discount_cents
    return 0 unless applied_discount

    applied_discount.amount_for(subtotal_cents)
  end

  def shipping_cents
    return 0 unless store

    net = [ subtotal_cents - discount_cents, 0 ].max
    return 0 if store.free_shipping?(net)

    sendit = Sendit::Districts.shipping_cents_for(city: city, district: district, address: address)
    return sendit if sendit

    # Fallback when Sendit is off or the city isn't in their list yet
    store.shipping_cents.to_i
  end

  def total_cents
    [ subtotal_cents - discount_cents + shipping_cents, 0 ].max
  end

  def applied_discount
    return @applied_discount if defined?(@applied_discount)

    code = discount_code.to_s.strip.upcase
    @applied_discount = code.present? ? store&.discounts&.current&.find_by(code: code) : nil
  end


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

  # Cities like Casablanca have many Sendit districts — quartier is required to pin the parcel
  def self.district_required_for?(city)
    districts_by_city[city].to_a.size > 1
  end

  def district_required?
    self.class.district_required_for?(city)
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
        subtotal_cents: subtotal_cents,
        discount_cents: discount_cents,
        discount_code: applied_discount&.code,
        shipping_cents: shipping_cents,
        total_cents: total_cents,
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

    match = if district.present?
      Sendit::Districts.match(city: city, address: district)
    else
      Sendit::Districts.match(city: city, address: address.to_s)
    end
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

  def district_must_be_valid
    return unless city.present? && district_required?

    areas = self.class.districts_by_city[city]
    if district.blank?
      errors.add(:district, :blank, message: I18n.t("checkout.errors.district"))
    elsif areas.exclude?(district)
      errors.add(:district, :invalid, message: I18n.t("checkout.errors.district_invalid"))
    end
  end

  def phone_must_be_moroccan
    return if phone.blank? || self.class.normalize_phone(phone)

    errors.add(:phone, :invalid, message: I18n.t("checkout.errors.phone_format"))
  end

  def cart_must_have_items
    errors.add(:base, I18n.t("checkout.errors.empty_cart")) if cart.nil? || cart.empty?
  end

  def discount_must_be_valid
    return if discount_code.blank?
    return if applied_discount

    errors.add(:discount_code, :invalid, message: I18n.t("checkout.errors.discount_code"))
  end
end

