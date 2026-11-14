# The figures of the delivery management page, calculated from the store's own orders (never from a carrier call). A parcel is an order that left for delivery: its status is not
# new / confirmed / cancelled, or it has a Sendit code (the same cohort as Admin::DeliverySummary). The period applies to the order date or to the shipping date (basis).
#
#   delivery rate   = delivered / parcels            return rate = (returned + returning) / parcels
#   average days    = mean(delivered_at - shipped_at) of the delivered parcels (negative or missing times are left out)
#   cost / delivered = (carrier delivery fees of the delivered + carrier return fees of the returned) / delivered
#   COD collected   = total of the delivered parcels; "paid out" = what the carrier already handed over (collected_cents); "due" = the difference
# Every query is scoped to the store.
class DeliveryAnalytics
  BASES = %w[order ship].freeze
  COMPANIES = %w[all sendit manual].freeze
  # Parcel stages for the donut, in order: [key, the statuses it holds].
  STAGES = %w[delivered returned return_in_progress waiting failed in_transit out_for_delivery].freeze
  DELAY_BUCKETS = [ [ "lt1", 0, 1 ], [ "1_2", 1, 2 ], [ "2_3", 2, 3 ], [ "3_5", 3, 5 ], [ "5plus", 5, nil ] ].freeze
  VALUE_BANDS = [ [ "lt200", 0, 200 ], [ "200_299", 200, 300 ], [ "300_449", 300, 450 ], [ "450plus", 450, nil ] ].freeze
  STUCK_AFTER = 3.days
  MIN_PARCELS_FOR_RATE = 3

  Parcel = Data.define(:id, :status, :total, :delivery_fee, :return_fee, :collected, :collected_at, :shipped_at, :delivered_at, :created_at, :city, :sendit, :return_status, :synced_at, :source) do
    def delivered? = status == "delivered"
    def returned? = status == "returned"
    def return_in_progress? = returned? && return_status.present? && !Sendit::Sync::RETURN_DONE.include?(return_status.to_s.upcase)
    def failed? = Order::PROBLEM_STATUSES.include?(status)
    def day = (shipped_at || created_at)

    def stage
      return "delivered" if delivered?
      return (return_in_progress? ? "return_in_progress" : "returned") if returned?
      return "failed" if failed?
      return "out_for_delivery" if status == "out_for_delivery"
      return "in_transit" if %w[picked_up in_transit].include?(status)

      "waiting"
    end

    def days
      return unless delivered? && shipped_at && delivered_at && delivered_at >= shipped_at

      (delivered_at - shipped_at) / 86_400.0
    end
  end

  Group = Data.define(:key, :parcels, :delivered, :returned, :returning, :fees, :days)

  attr_reader :range, :basis, :company

  def initialize(store:, range:, basis: "order", company: "all", now: Time.current)
    @store, @range, @now = store, range, now
    @basis = BASES.include?(basis.to_s) ? basis.to_s : "order"
    @company = COMPANIES.include?(company.to_s) ? company.to_s : "all"
  end

  def parcels
    @parcels ||= load_parcels
  end

  def total = parcels.size
  def delivered = parcels.select(&:delivered?)
  def returned = parcels.select(&:returned?)
  def delivered_count = delivered.size
  def returned_count = returned.size
  def returning_count = parcels.count(&:return_in_progress?)

  def delivery_rate = percent(delivered_count, total)
  def return_rate = percent(returned_count, total)

  def average_days = mean(delivered.filter_map(&:days))&.round(1)

  # Share of the delivered parcels that arrived within two days.
  def fast_share = (days = delivered.filter_map(&:days)).empty? ? nil : percent(days.count { |value| value <= 2 }, days.size)

  def delivery_fees = delivered.sum { |parcel| parcel.delivery_fee.to_i }
  def return_fees = returned.sum { |parcel| parcel.return_fee.to_i }
  def fees = delivery_fees + return_fees
  def cost_per_delivered = delivered_count.zero? ? nil : fees.fdiv(delivered_count)
  def average_order = delivered_count.zero? ? nil : cod_total.fdiv(delivered_count)
  def cost_share = (cost = cost_per_delivered) && average_order&.positive? ? (cost * 100.0 / average_order).round(2) : nil
  # Parcels whose carrier fee is not known yet: the cost above is then a minimum.
  def missing_fees = delivered.count { |parcel| parcel.delivery_fee.nil? } + returned.count { |parcel| parcel.return_fee.nil? }

  def cod_total = delivered.sum(&:total)
  def paid_out = delivered.sum { |parcel| parcel.collected_at ? parcel.collected.to_i : 0 }
  def due = [ cod_total - paid_out, 0 ].max
  def after_fees = cod_total - fees
  def paid_share = percent(paid_out, cod_total)

  # { stage => { count:, cod: } } in STAGES order.
  def stages
    @stages ||= STAGES.to_h do |stage|
      list = parcels.select { |parcel| parcel.stage == stage }
      [ stage, { count: list.size, cod: list.sum(&:total) } ]
    end
  end

  def cities(limit: 12)
    group(parcels.group_by { |parcel| parcel.city.to_s.strip.presence || "—" }).first(limit)
  end

  def sources = group(parcels.group_by(&:source))

  def value_bands
    VALUE_BANDS.map do |key, from, to|
      list = parcels.select { |parcel| (mad = parcel.total / 100.0) >= from && (to.nil? || mad < to) }
      { key: key, parcels: list.size, delivered: list.count(&:delivered?), rate: percent(list.count(&:delivered?), list.size) }
    end
  end

  def delay_buckets
    days = delivered.filter_map(&:days)
    DELAY_BUCKETS.map { |key, from, to| { key: key, count: days.count { |value| value >= from && (to.nil? || value < to) } } }
  end

  # One entry per store day of the period (at most the last 62), by shipping day.
  def daily
    @daily ||= begin
      by_day = parcels.group_by { |parcel| parcel.day.in_time_zone(DateRange::ZONE).to_date }
      days = ((range.begin.in_time_zone(DateRange::ZONE).to_date)..(range.end.in_time_zone(DateRange::ZONE).to_date)).to_a.last(62)
      days.map do |day|
        list = by_day.fetch(day, [])
        sent = list.size
        { day: day, parcels: sent, delivered: list.count(&:delivered?), returned: list.count(&:returned?), other: list.count { |parcel| !parcel.delivered? && !parcel.returned? },
          rate: sent >= MIN_PARCELS_FOR_RATE ? percent(list.count(&:delivered?), sent) : nil }
      end
    end
  end

  # What needs a call or a look now.
  def problems
    failed = parcels.select(&:failed?)
    stuck = parcels.select { |parcel| %w[picked_up in_transit out_for_delivery].include?(parcel.status) && (parcel.synced_at.nil? || parcel.synced_at < @now - STUCK_AFTER) }
    returning = parcels.select(&:return_in_progress?)
    { failed: { count: failed.size, cod: failed.sum(&:total) }, returning: { count: returning.size, cod: returning.sum(&:total) }, stuck: { count: stuck.size, cod: stuck.sum(&:total) } }
  end

  # Why parcels did not arrive: the share of each cause among the failed and returned parcels.
  def failure_causes
    counts = { "unreachable" => 0, "address_issue" => 0, "postponed" => 0, "returned" => 0 }
    parcels.each do |parcel|
      if parcel.returned? then counts["returned"] += 1
      elsif parcel.failed? then counts[parcel.status] += 1
      end
    end
    all = counts.values.sum
    counts.map { |key, count| { key: key, count: count, share: percent(count, all) } }.reject { |row| row[:count].zero? }.sort_by { |row| -row[:count] }
  end

  private

  def load_parcels
    column = basis == "ship" ? :shipped_at : :created_at
    scope = @store.orders.where(column => range)
    scope = scope.where.not(status: %w[new confirmed cancelled]).or(scope.where.not(sendit_code: [ nil, "" ])).where.not(status: "new")
    scope = scope.where.not(sendit_code: [ nil, "" ]) if company == "sendit"
    scope = scope.where(sendit_code: [ nil, "" ]) if company == "manual"
    rows = scope.pluck(:id, :status, :total_cents, :delivery_fee_cents, :return_fee_cents, :collected_cents, :collected_at, :shipped_at, :delivered_at, :created_at,
                       :customer_city, :sendit_code, :sendit_return_status, :sendit_synced_at)
    sources = ExternalOrderReceipt.where(order_id: rows.map(&:first)).joins(:store_connection).pluck(:order_id, "store_connections.provider").to_h
    rows.map do |id, status, total, delivery_fee, return_fee, collected, collected_at, shipped_at, delivered_at, created_at, city, sendit_code, return_status, synced_at|
      Parcel.new(id: id, status: status, total: total.to_i, delivery_fee: delivery_fee, return_fee: return_fee, collected: collected, collected_at: collected_at, shipped_at: shipped_at,
                 delivered_at: delivered_at, created_at: created_at, city: city, sendit: sendit_code.present?, return_status: return_status, synced_at: synced_at, source: sources[id].presence || "manual")
    end
  end

  def group(buckets)
    buckets.map do |key, list|
      Group.new(key: key, parcels: list.size, delivered: list.count(&:delivered?), returned: list.count(&:returned?), returning: list.count(&:return_in_progress?),
                fees: list.sum { |parcel| parcel.delivered? ? parcel.delivery_fee.to_i : (parcel.returned? ? parcel.return_fee.to_i : 0) }, days: mean(list.filter_map(&:days))&.round(1))
    end.sort_by { |row| [ -row.parcels, row.key.to_s ] }
  end

  def percent(part, whole) = whole.to_i.zero? ? nil : (part * 100.0 / whole).round(2)

  def mean(values) = values.empty? ? nil : values.sum / values.size
end
