# frozen_string_literal: true

# Money formatting still used by the delivery and platform pages until they are ported to the seller design.
module DashboardMoneyHelper
  def dashboard_money(cents, currency = "MAD")
    number_to_currency(BigDecimal(cents.to_i.to_s) / 100, unit: currency == "DH" ? "MAD" : currency, format: "%n %u", precision: 2)
  end
end
