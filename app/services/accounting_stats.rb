# frozen_string_literal: true

# The one place where a workspace's accounting figures are calculated. The Comptabilité cards, the export and
# anything else that shows these numbers read this class, so they are identical everywhere.
#
# How it stays exact:
# - Every amount is a whole number of centimes. Nothing is a float. Ratios are Rational (exact fractions),
#   and the only rounding is done by the view when it prints a number.
# - Everything is built from *lines*: one per delivered order, one per returned order, one per day of ad spend.
#   Totals, daily curves and the export are sums of these same lines, so they cannot disagree.
# - The cost of goods is the unit cost frozen on each order line when the order was placed, and the delivery and
#   return fees are the ones frozen on the order when it was delivered or returned. Changing a product's cost
#   or a carrier's fee later does not move old months.
# - Months and days are Africa/Casablanca days.
#
# Which orders count (money only comes in when a COD order is delivered):
# - Livrées:   delivered orders by delivered_at; returned orders by returned_at.
# - Expédiées: delivered orders by shipped_at;   returned orders by shipped_at.
# - Delivered orders carry revenue, cost of goods and their delivery fee.
# - Returned or refused orders carry no revenue and no cost of goods (the product is back in stock); their return
#   fee is an expense.
# - New, confirmed, cancelled, in transit, unreachable and postponed orders never count.
#
#   gross margin   = revenue - cost of goods
#   total expenses = cost of goods + delivery fees (delivery and return) + advertising
#   net profit     = revenue - total expenses            (so expenses + net profit = revenue)
class AccountingStats
  ZONE = "Africa/Casablanca"
  BASES = %w[delivered shipped].freeze
  TENTHS = 1000 # shares are computed in tenths of a point, so 100.0 is exactly 1000

  Line = Struct.new(:date, :kind, :order_id, :number, :revenue, :goods, :delivery, :ads, keyword_init: true)

  Totals = Struct.new(:orders, :revenue, :goods, :delivery, :ads, keyword_init: true) do
    def gross_margin = revenue - goods
    def expenses = goods + delivery + ads
    def net = revenue - expenses
    # nil (shown as a dash) when there is nothing to divide by, never 0 and never an error.
    def average_basket = orders.positive? ? Rational(revenue, orders) : nil
    def margin = revenue.positive? ? Rational(net, revenue) : nil
  end

  attr_reader :basis, :range, :previous_range

  def initialize(store:, month: nil, basis: "delivered", now: Time.current)
    @store = store
    @basis = BASES.include?(basis.to_s) ? basis.to_s : "delivered"
    @today = now.in_time_zone(ZONE).to_date
    @month = parse_month(month)
    last_day = [ @month.end_of_month, @today ].min
    @range = @month..last_day
    days = (@range.end - @range.begin).to_i + 1
    @previous_range = (@range.begin - days)..(@range.begin - 1)
  end

  def month = @month

  def currency
    code = @store.currency.to_s.upcase
    code == "DH" ? "MAD" : code
  end

  def lines = @lines ||= build_lines(@range)
  def totals = @totals ||= totals_of(lines)
  def previous_lines = @previous_lines ||= build_lines(@previous_range)
  def previous_totals = @previous_totals ||= totals_of(previous_lines)

  # Totals of each day of the month (a Totals for every day, empty days included), for the small curves.
  def daily
    @daily ||= begin
      by_day = lines.group_by(&:date)
      @range.to_h { |day| [ day, totals_of(by_day.fetch(day, [])) ] }
    end
  end

  # Change versus the previous period of the same length: an exact percentage (Rational), :new when the previous
  # value was 0, or nil when there is nothing to compare (both 0, or a ratio that does not exist).
  def change(metric)
    current = totals.public_send(metric)
    previous = previous_totals.public_send(metric)
    return nil if current.nil? || previous.nil?
    return (current.zero? ? nil : :new) if previous.zero?

    Rational(current - previous) * 100 / previous.abs
  end

  # Profit margin moves in points, not in percent of a percent. nil when either month has no revenue.
  def margin_change_points
    return nil if totals.margin.nil? || previous_totals.margin.nil?

    (totals.margin - previous_totals.margin) * 100
  end

  # How each 100 of revenue splits, in tenths of a point (integers adding up to exactly 1000, i.e. 100.0).
  # nil without revenue. When the month loses money, profit is 0 and the three expenses share the 100.
  def split_per_100
    return nil unless totals.revenue.positive?

    loss = totals.net.negative?
    parts = { goods: totals.goods, delivery: totals.delivery, ads: totals.ads, profit: loss ? 0 : totals.net }
    { shares: largest_remainder(parts, parts.values.sum), loss: loss }
  end

  # Cost of goods by product, then by variant, from the frozen unit costs of the delivered orders counted above.
  # A product (or variant) shows one unit cost when all its units were bought at the same cost, nil when the cost
  # changed in between. The product totals add up to totals.goods (checked in #invariants).
  def goods_breakdown
    @goods_breakdown ||= begin
      ids = lines.select { |line| line.kind == "delivered" }.map(&:order_id)
      rows = OrderItem.where(order_id: ids).group(:product_name, :variant_name, :unit_cost_cents).sum(:quantity)
      rows.group_by { |(product, _variant, _cost), _quantity| product }.map do |product, entries|
        variants = entries.group_by { |(_p, variant, _cost), _quantity| variant }.map do |variant, parts|
          cost_line(variant, parts.map { |(_p, _v, cost), quantity| [ cost, quantity ] })
        end
        cost_line(product, entries.map { |(_p, _v, cost), quantity| [ cost, quantity ] }).merge(variants: variants.sort_by { |variant| [ -variant[:cents], variant[:name].to_s ] })
      end.sort_by { |product| [ -product[:cents], product[:name].to_s ] }
    end
  end

  # Delivery fees of delivered parcels, and return fees of returned ones (their sum is totals.delivery).
  def delivery_split
    @delivery_split ||= {
      delivered: lines.select { |line| line.kind == "delivered" }.sum(&:delivery),
      returned: lines.select { |line| line.kind == "returned" }.sum(&:delivery)
    }
  end

  # Things the merchant must know before trusting the figures. Counts of delivered or returned orders in the month.
  def warnings
    @warnings ||= begin
      delivered_ids = lines.select { |line| line.kind == "delivered" }.map(&:order_id)
      returned_ids = lines.select { |line| line.kind == "returned" }.map(&:order_id)
      {
        missing_cost_orders: OrderItem.where(order_id: delivered_ids, unit_cost_cents: nil).distinct.count(:order_id),
        missing_delivery_fee_orders: @store.orders.where(id: delivered_ids, delivery_fee_cents: nil).count,
        missing_return_fee_orders: @store.orders.where(id: returned_ids, return_fee_cents: nil).count,
        unconverted_ad_rows: ad_rows.where(spend_display: nil).or(ad_rows.where.not(display_currency: currency)).count
      }
    end
  end

  # Amounts as of today, not tied to the month.
  # Delivered parcels whose cash has not been recorded as received.
  def receivables
    @receivables ||= begin
      pending = orders.awaiting_remittance
      { cents: pending.sum(:total_cents), parcels: pending.count }
    end
  end

  # Stock at purchase price. Products without a purchase cost are left out and counted.
  def inventory
    @inventory ||= begin
      products = @store.products.includes(:product_variants)
      value = 0
      missing = 0
      out_of_stock = 0
      products.each do |product|
        units = product.product_variants.any? ? product.product_variants.sum(&:stock) : product.stock
        out_of_stock += 1 if units <= 0
        if product.cost_cents.nil? then missing += 1 else value += units * product.cost_cents end
      end
      { cents: value, products: products.size, out_of_stock: out_of_stock, missing_cost: missing }
    end
  end

  # Checks that must always hold. An empty list means the figures are consistent.
  def invariants
    failures = []
    t = totals
    failures << "gross margin" unless t.gross_margin == t.revenue - t.goods
    failures << "expenses + net = revenue" unless t.expenses + t.net == t.revenue
    split = split_per_100
    failures << "split adds up to 100" if split && split[:shares].values.sum != TENTHS
    failures << "totals = sum of lines" unless [ t.revenue, t.goods, t.delivery, t.ads ] ==
      [ lines.sum(&:revenue), lines.sum(&:goods), lines.sum(&:delivery), lines.sum(&:ads) ]
    failures << "daily = month" unless daily.values.sum(&:revenue) == t.revenue && daily.values.sum(&:net) == t.net
    failures << "goods by product = goods" unless goods_breakdown.sum { |product| product[:cents] } == t.goods
    failures << "delivery split = delivery" unless delivery_split.values.sum == t.delivery
    failures
  end

  private

  def parse_month(value)
    parsed = Date.strptime("#{value}-01", "%Y-%m-%d") if value.to_s.match?(/\A\d{4}-(0[1-9]|1[0-2])\z/)
    parsed = nil if parsed && parsed > @today.beginning_of_month
    parsed || @today.beginning_of_month
  end

  def orders
    @orders ||= @store.orders.where(currency: currency == "MAD" ? %w[DH MAD] : [ currency ])
  end

  # [start, finish) in absolute time for whole Casablanca days.
  def window(period)
    zone = Time.find_zone!(ZONE)
    [ zone.local(period.begin.year, period.begin.month, period.begin.day), zone.local(period.end.year, period.end.month, period.end.day) + 1.day ]
  end

  def build_lines(period)
    start, finish = window(period)
    delivered_column = basis == "shipped" ? :shipped_at : :delivered_at
    returned_column = basis == "shipped" ? :shipped_at : :returned_at

    delivered = orders.where(status: "delivered", delivered_column => start...finish)
      .pluck(:id, :number, delivered_column, :total_cents, :delivery_fee_cents)
    goods = OrderItem.where(order_id: delivered.map(&:first)).group(:order_id).sum(Arel.sql("quantity * COALESCE(unit_cost_cents, 0)"))
    result = delivered.map do |id, number, at, total, fee|
      Line.new(date: day_of(at), kind: "delivered", order_id: id, number: number, revenue: total, goods: goods.fetch(id, 0), delivery: fee.to_i, ads: 0)
    end

    returned = orders.where(status: "returned", returned_column => start...finish).pluck(:id, :number, returned_column, :return_fee_cents)
    result += returned.map do |id, number, at, fee|
      Line.new(date: day_of(at), kind: "returned", order_id: id, number: number, revenue: 0, goods: 0, delivery: fee.to_i, ads: 0)
    end

    result + ad_lines(period)
  end

  # Advertising: Meta spend already converted to the store's currency (campaign rows; ad rows are the same money
  # seen at another level). A day's decimal amounts are added first and turned into centimes once, half up.
  # Rows in another currency or without a conversion are left out and reported, never mixed in.
  def ad_rows_for(period)
    MetaAds::DailyInsight.where(store_id: @store.id, level: "campaign", date: period.begin..period.end)
  end

  def ad_rows = ad_rows_for(@range)

  def ad_lines(period)
    ad_rows_for(period).where(display_currency: currency).where.not(spend_display: nil).group(:date).sum(:spend_display).filter_map do |day, spend|
      cents = (spend * 100).round(0, half: :up).to_i
      Line.new(date: day, kind: "ads", order_id: nil, number: nil, revenue: 0, goods: 0, delivery: 0, ads: cents) if cents.positive?
    end
  end

  def day_of(time) = time.in_time_zone(ZONE).to_date

  # One row of the goods breakdown from [unit cost, quantity] pairs; a missing cost counts as 0.
  def cost_line(name, pairs)
    costs = pairs.map { |cost, _quantity| cost.to_i }.uniq
    { name: name, quantity: pairs.sum { |_cost, quantity| quantity }, cents: pairs.sum { |cost, quantity| cost.to_i * quantity },
      unit_cost_cents: (costs.first if costs.one?) }
  end

  def totals_of(list)
    Totals.new(orders: list.count { |line| line.kind == "delivered" }, revenue: list.sum(&:revenue), goods: list.sum(&:goods),
      delivery: list.sum(&:delivery), ads: list.sum(&:ads))
  end

  # Integer shares of `total` for each part, in tenths, adding up to exactly TENTHS: the biggest remainders get the
  # last units. Ties go to the first part.
  def largest_remainder(parts, total)
    floors = parts.transform_values { |amount| amount * TENTHS / total }
    left = TENTHS - floors.values.sum
    order = parts.keys.sort_by.with_index { |key, index| [ -((parts[key] * TENTHS) % total), index ] }
    order.first(left).each { |key| floors[key] += 1 }
    floors
  end
end
