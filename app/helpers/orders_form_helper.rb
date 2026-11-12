# frozen_string_literal: true

# The data the order form's scripts need: the city list and rates, the currency, the endpoints. One place for the
# full form and the new-order window, which differ only in the name of the controller that drives the products part.
module OrdersFormHelper
  # What a delivery company offers for an address: its cities, the districts of each city and the delivery price of each city
  # (cents). Only a company with an API list has one (today Sendit); any other company returns nothing, and the city is typed.
  def company_city_catalog(provider)
    return { cities: [], districts: {}, rates: {} } unless provider.to_s == "sendit"

    { cities: Checkout.cities(current_store), districts: Checkout.districts_by_city(current_store),
      rates: Sendit::Districts.shipping_cents_by_city(store: current_store) }
  end

  # identifier: "order-lines" (full form) or "order-composer" (new-order window), both with the city picker "checkout-city".
  # company_providers: given by the new-order window only; the cities then come from the company chosen in the form (none
  # until one is chosen) and change when another is chosen.
  def order_form_context(order, identifier: "order-lines", company_providers: nil)
    currency = order.currency.presence || current_store.currency
    by_company = !company_providers.nil?
    catalogs = by_company ? company_providers.index_with { |provider| company_city_catalog(provider) } : {}
    initial = by_company ? (catalogs[order.delivery_provider.to_s] || company_city_catalog(nil)) : nil
    cities = initial ? initial[:cities] : Checkout.cities(current_store)
    districts_by_city = initial ? initial[:districts] : Checkout.districts_by_city(current_store)
    rates = initial ? initial[:rates] : (cities.any? ? Sendit::Districts.shipping_cents_by_city(store: current_store) : {})
    key = identifier.tr("-", "_")
    data = {
      controller: [ identifier, "checkout-city", ("delivery-company" if by_company) ].compact.join(" "),
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
    data.merge!(checkout_city_cities_value: cities, checkout_city_districts_value: districts_by_city, checkout_city_rates_value: rates) if cities.any?
    data[:delivery_company_catalogs_value] = catalogs if by_company
    { data: data, currency: currency, cities: cities, districts_by_city: districts_by_city,
      district_required: districts_by_city[order.customer_city].to_a.size > 1,
      district_options: districts_by_city[order.customer_city].to_a }
  end
end
