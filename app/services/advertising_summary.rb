class AdvertisingSummary
  attr_reader :accounts, :campaigns, :start_date, :end_date, :rows, :daily

  def initialize(store:, start_date: nil, end_date: nil, sort: nil)
    raise ArgumentError, "Persisted store required" unless store.is_a?(Store) && store.persisted?
    @end_date = parse_date(end_date) || Time.current.in_time_zone("Africa/Casablanca").to_date
    @start_date = parse_date(start_date) || @end_date - 29
    @start_date = @end_date - 365 if @start_date < @end_date - 365
    @start_date = @end_date if @start_date > @end_date
    @accounts = AdvertisingAccount.where(store: store).order(:name)
    @campaigns = AdvertisingCampaign.where(advertising_account_id: @accounts.select(:id)).includes(:advertising_account).order(:name)
    performance = AdvertisingPerformance.where(advertising_campaign_id: @campaigns.select(:id), date: @start_date..@end_date)
    grouped = performance.group(:advertising_campaign_id).pluck(:advertising_campaign_id, *AdvertisingPerformance::METRICS.map { |metric| AdvertisingPerformance.arel_table[metric].sum })
    totals = grouped.to_h { |id, *values| [id, AdvertisingPerformance::METRICS.zip(values).to_h] }
    @rows = @campaigns.map { |campaign| { campaign: campaign, metrics: totals.fetch(campaign.id, empty_metrics) } }
    @rows.sort_by! { |row| -profit(row[:metrics]) } if sort == 'profit'
    @daily = performance.group(:date).order(:date).pluck(:date, Arel.sql('SUM(spend_cents)'), Arel.sql('SUM(delivered_revenue_cents)'))
  end

  def totals
    AdvertisingPerformance::METRICS.to_h { |metric| [metric, rows.sum { |row| row[:metrics][metric] }] }
  end

  def profit(metrics)
    metrics[:delivered_revenue_cents] - metrics[:spend_cents] - metrics[:fulfillment_cost_cents]
  end

  def roas(metrics)
    metrics[:spend_cents].positive? ? metrics[:delivered_revenue_cents].fdiv(metrics[:spend_cents]) : nil
  end

  private

  def empty_metrics
    AdvertisingPerformance::METRICS.index_with { 0 }
  end

  def parse_date(value)
    Date.iso8601(value.to_s)
  rescue Date::Error
    nil
  end
end
