# frozen_string_literal: true

# Subscription plans and price helpers, ported from the seallo platform (config/plans.yml).
# Prices are whole US dollars; they are converted for display into the customer's currency.
module Plans
  CONFIG = YAML.safe_load_file(Rails.root.join("config/plans.yml")).freeze
  BILLINGS = %w[monthly annual].freeze

  module_function

  def config
    CONFIG.merge("bank" => bank)
  end

  def list = CONFIG.fetch("list")
  def currencies = CONFIG.fetch("currencies")
  def reference_currency = CONFIG.fetch("currency")
  def trial_days = CONFIG.fetch("trial_days")
  def annual_months_paid = CONFIG.fetch("annual_months_paid")
  def card_enabled? = CONFIG.fetch("card_enabled")

  def bank
    defaults = CONFIG.fetch("bank")
    {
      "holder" => ENV["SEALLO_BANK_HOLDER"].presence || defaults["holder"],
      "bank" => ENV["SEALLO_BANK_NAME"].presence || defaults["bank"],
      "rib" => ENV["SEALLO_BANK_RIB"].presence || defaults["rib"],
      "swift" => ENV["SEALLO_BANK_SWIFT"].presence || defaults["swift"]
    }
  end

  def plan(key) = list[key.to_s]
  def plan?(key) = list.key?(key.to_s)
  def currency?(code) = currencies.key?(code.to_s)
  def free?(key) = plan(key).nil? || plan(key)["price"].to_i.zero?

  # Amount due for a plan, in dollars.
  def amount_due(key, billing)
    price = plan(key)&.fetch("price").to_i
    billing.to_s == "annual" ? price * annual_months_paid : price
  end

  def monthly_price(plan, billing)
    billing.to_s == "annual" ? plan["price"] * annual_months_paid / 12.0 : plan["price"]
  end

  def yearly_total(plan) = plan["price"] * annual_months_paid
  def annual_saving = ((1 - annual_months_paid / 12.0) * 100).round

  # Converts dollars to the chosen currency, rounded the same way as the seallo pricing page.
  def convert(usd, code)
    rate = currencies.dig(code.to_s, "rate") || 1
    value = usd * rate
    return 0 if value.zero?

    rate >= 50 ? (value / 10.0).round * 10 : value.round
  end

  def money(usd, code)
    currency = currencies[code.to_s] || { "symbol" => code.to_s, "rate" => 1 }
    amount = ActiveSupport::NumberHelper.number_to_delimited(convert(usd, code), delimiter: " ")
    symbol = currency["symbol"]
    # ⁦..⁩ keeps the amount left-to-right inside Arabic text.
    text = case symbol
    when "$", "£" then "#{symbol}#{amount}"
    when "€" then "#{amount} €"
    else "#{amount} #{symbol}"
    end
    "⁦#{text}⁩"
  end
end
