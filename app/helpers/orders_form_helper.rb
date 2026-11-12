# frozen_string_literal: true

# The data the order form's scripts need: the city list and rates (Sendit), the currency, the endpoints. One place for the
# full form and the new-order window, which differ only in the name of the controller that drives the products part.
module OrdersFormHelper
  # identifier: "order-lines" (full form) or "order-composer" (new-order window), both with the city picker "checkout-city".
  def order_form_context(order, identifier: "order-lines")
    currency = order.currency.presence || current_store.currency
    cities = Checkout.cities(current_store)
    districts_by_city = Checkout.districts_by_city(current_store)
    key = identifier.tr("-", "_")
    data = {
      controller: "#{identifier} checkout-city",
      "#{key}_search_url_value": product_search_admin_orders_path,
      "#{key}_quick_url_value": quick_product_admin_orders_path,
      "#{key}_currency_value": currency,
      action: "submit->checkout-city#validateCity input->#{identifier}#recalc change->#{identifier}#recalc click->#{identifier}#recalcSoon",
      checkout_city_subtotal_value: order.subtotal_cents.to_i,
      checkout_city_discount_value: order.discount_cents.to_i,
      checkout_city_free_threshold_value: current_store.free_shipping_threshold_cents.to_i,
      checkout_city_currency_value: currency,
      checkout_city_locale_value: "en-MA",
      checkout_city_free_label_value: "Free",
      checkout_city_pending_label_value: "Select a city",
      checkout_city_confirm_template_value: "%{total}",
      checkout_city_choose_district_value: "Choose district",
      checkout_city_no_match_value: "No matching city"
    }
    if cities.any?
      data.merge!(checkout_city_cities_value: cities, checkout_city_districts_value: districts_by_city,
                  checkout_city_rates_value: Sendit::Districts.shipping_cents_by_city(store: current_store))
    end
    { data: data, currency: currency, cities: cities, districts_by_city: districts_by_city,
      district_required: Checkout.district_required_for?(order.customer_city, store: current_store),
      district_options: districts_by_city[order.customer_city].to_a }
  end
end
