# frozen_string_literal: true

# One day's rate between two currencies, as published by the rate source: 1 base = rate quote.
class ExchangeRate < ApplicationRecord
  validates :base_currency, :quote_currency, format: { with: /\A[A-Z]{3}\z/ }
  validates :rate, numericality: { greater_than: 0 }
  validates :rate_date, :source, :fetched_at, presence: true
  validates :rate_date, uniqueness: { scope: %i[base_currency quote_currency] }
end
