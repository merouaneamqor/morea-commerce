# frozen_string_literal: true

module MetaAds
  # Tenant-scoped campaign follow-up for the Meta Ads page: status, budgets, range spend/ROAS,
  # running ads and the linked product. Uses campaign-level insights only (never add ad rows).
  class CampaignOverview
    Row = Struct.new(
      :campaign, :ad_account, :product, :link_source, :spend, :spend_display, :impressions, :clicks,
      :conversions, :conversion_value, :roas, :currency, :display_currency, :daily_budget, :lifetime_budget,
      :budget_remaining, :budget_level, :active_ads, :total_ads, :effective_status, :status, :objective,
      keyword_init: true
    )

    def initialize(store:, range:)
      @store = store
      @range = range
    end

    def rows
      @rows ||= build_rows
    end

    def totals
      @totals ||= begin
        spend = rows.sum { |row| row.spend_display || row.spend || 0 }
        value = rows.sum { |row| row.conversion_value || 0 }
        {
          spend: spend,
          conversions: rows.sum { |row| row.conversions || 0 },
          conversion_value: value,
          roas: spend.positive? && value.positive? ? (value / spend).round(4) : nil,
          currency: @store.currency,
          active_campaigns: rows.count { |row| row.effective_status.to_s == "ACTIVE" },
          campaigns: rows.size
        }
      end
    end

    private

    def build_rows
      campaigns = MetaAds::Campaign.where(store_id: @store.id)
        .includes(:ad_account)
        .where(ad_account_id: MetaAds::AdAccount.where(store_id: @store.id, selected: true).select(:id))
        .order(:name, :meta_id)
      return [] if campaigns.empty?

      metrics = metrics_by_campaign
      links = ProductLink.where(store_id: @store.id, object_type: "campaign").includes(:product).index_by(&:meta_id)
      ad_counts = MetaAds::Ad.where(store_id: @store.id, campaign_id: campaigns.map(&:id))
        .group(:campaign_id)
        .pluck(
          Arel.sql("campaign_id"),
          Arel.sql("COUNT(*)"),
          Arel.sql("COUNT(*) FILTER (WHERE effective_status = 'ACTIVE')")
        )
        .to_h { |campaign_id, total, active| [ campaign_id, [ total, active ] ] }
      ad_set_budgets = MetaAds::AdSet.where(store_id: @store.id, campaign_id: campaigns.map(&:id))
        .group(:campaign_id)
        .pluck(
          Arel.sql("campaign_id"),
          Arel.sql("COALESCE(SUM(daily_budget), 0)"),
          Arel.sql("COALESCE(SUM(lifetime_budget), 0)"),
          Arel.sql("COALESCE(SUM(budget_remaining), 0)")
        )
        .to_h { |campaign_id, daily, lifetime, remaining| [ campaign_id, [ daily, lifetime, remaining ] ] }

      campaigns.filter_map do |campaign|
        figures = metrics[campaign.id] || empty_metrics
        next if figures[:spend].zero? && campaign.effective_status.blank? && campaign.last_seen_at.blank?

        link = links[campaign.meta_id]
        daily, lifetime, remaining, budget_level = budgets_for(campaign, ad_set_budgets[campaign.id])
        total_ads, active_ads = ad_counts[campaign.id] || [ 0, 0 ]
        Row.new(
          campaign: campaign,
          ad_account: campaign.ad_account,
          product: link&.product,
          link_source: link&.source,
          spend: figures[:spend],
          spend_display: figures[:spend_display],
          impressions: figures[:impressions],
          clicks: figures[:clicks],
          conversions: figures[:conversions],
          conversion_value: figures[:conversion_value],
          roas: figures[:roas],
          currency: figures[:currency] || campaign.ad_account.currency,
          display_currency: figures[:display_currency] || @store.currency,
          daily_budget: daily,
          lifetime_budget: lifetime,
          budget_remaining: remaining,
          budget_level: budget_level,
          active_ads: active_ads,
          total_ads: total_ads,
          effective_status: campaign.effective_status.presence || campaign.status,
          status: campaign.status,
          objective: campaign.objective
        )
      end.sort_by { |row| [ -(row.spend_display || row.spend).to_f, row.campaign.name.to_s ] }
    end

    def metrics_by_campaign
      MetaAds::DailyInsight.where(store_id: @store.id, level: "campaign", date: @range.from..@range.to)
        .group(:campaign_id, :currency, :display_currency)
        .pluck(
          Arel.sql("campaign_id"),
          Arel.sql("currency"),
          Arel.sql("display_currency"),
          Arel.sql("COALESCE(SUM(spend), 0)"),
          Arel.sql("COALESCE(SUM(spend_display), 0)"),
          Arel.sql("COALESCE(SUM(impressions), 0)"),
          Arel.sql("COALESCE(SUM(clicks), 0)"),
          Arel.sql("COALESCE(SUM(conversions), 0)"),
          Arel.sql("COALESCE(SUM(conversion_value), 0)")
        )
        .each_with_object({}) do |(campaign_id, currency, display_currency, spend, spend_display, impressions, clicks, conversions, value), map|
          spend = BigDecimal(spend.to_s)
          value = BigDecimal(value.to_s)
          map[campaign_id] = {
            currency: currency,
            display_currency: display_currency,
            spend: spend,
            spend_display: spend_display.present? ? BigDecimal(spend_display.to_s) : nil,
            impressions: impressions.to_i,
            clicks: clicks.to_i,
            conversions: BigDecimal(conversions.to_s),
            conversion_value: value,
            roas: spend.positive? && value.positive? ? (value / spend).round(4) : nil
          }
        end
    end

    def empty_metrics
      { spend: BigDecimal(0), spend_display: nil, impressions: 0, clicks: 0, conversions: BigDecimal(0),
        conversion_value: BigDecimal(0), roas: nil, currency: nil, display_currency: nil }
    end

    # Prefer campaign CBO budgets; otherwise roll up ad set budgets for the same campaign.
    def budgets_for(campaign, ad_set_totals)
      if campaign.daily_budget.present? || campaign.lifetime_budget.present?
        [ campaign.daily_budget, campaign.lifetime_budget, campaign.budget_remaining, "campaign" ]
      elsif ad_set_totals
        daily, lifetime, remaining = ad_set_totals
        daily = BigDecimal(daily.to_s)
        lifetime = BigDecimal(lifetime.to_s)
        remaining = BigDecimal(remaining.to_s)
        return [ nil, nil, nil, nil ] if daily.zero? && lifetime.zero?

        [ daily.positive? ? daily : nil, lifetime.positive? ? lifetime : nil, remaining.positive? ? remaining : nil, "ad_sets" ]
      else
        [ nil, nil, nil, nil ]
      end
    end
  end
end
