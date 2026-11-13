# frozen_string_literal: true

module MetaAds
  # Pulls daily spend for one selected ad account at campaign level and ad level, upserts it by
  # (ad account, campaign or ad, day) so a re-sync never duplicates, and converts spend to the store's currency.
  # First run: the last 30 days. After that: yesterday and today, because Meta revises recent numbers.
  # Days follow the ad account's own timezone.
  class InsightsSync
    BACKFILL_DAYS = 30
    LEVELS = { "campaign" => %w[campaign_id campaign_name], "ad" => %w[campaign_id campaign_name adset_id adset_name ad_id ad_name] }.freeze
    METRICS = %w[spend impressions reach clicks ctr cpc cpm actions action_values].freeze
    UNIQUE_INDEX = { "campaign" => :index_meta_ads_insights_campaign_day, "ad" => :index_meta_ads_insights_ad_day }.freeze
    # Meta reports the same purchase under several action types; count one of them, in this order.
    PURCHASE_TYPES = %w[omni_purchase purchase offsite_conversion.fb_pixel_purchase].freeze
    HIGH_USAGE_PCT = 75
    BACKOFF_BASE = 60
    MAX_BACKOFF = 1.hour
    ID_FORMAT = /\A\d{1,25}\z/

    def initialize(ad_account:, transport: nil, fx: Fx.new, now: Time.current)
      @account = ad_account
      @transport = transport
      @fx = fx
      @now = now
      @quotes = {}
      @objects = { campaign: {}, ad_set: {}, ad: {} }
    end

    # Returns the number of insight rows written, or nil when the account was skipped or the sync failed.
    def call
      connection = @account.connection
      return unless @account.selected? && connection.active?

      @store = @account.store
      @display_currency = Fx.normalize(@store.currency)
      @account.update!(sync_status: "running", last_attempt_at: @now)
      client = Client.new(connection: connection, transport: @transport)
      today = zone.at(@now).to_date
      since = @account.insights_backfilled_at ? today - 1 : today - BACKFILL_DAYS
      written = 0
      usage = 0
      # Structure first so the follow-up UI has statuses/budgets even when a day has no spend yet.
      usage = [ usage, StructureSync.new(ad_account: @account, client: client, now: @now).call ].max
      LEVELS.each_key do |level|
        response = client.collect("#{@account.meta_ad_account_id}/insights", insights_params(level, since, today))
        usage = [ usage, response.usage_pct ].max
        written += upsert_rows(level, response.data)
      end
      convert_missing
      ProductMatcher.call(store: @store)
      finish(usage)
      written
    rescue Client::AuthError, Client::PermissionError => error
      # Token expired or revoked (Meta error 190 and friends): stop syncing every account of the connection.
      connection.mark_needs_reauthorization!(error.code)
      nil
    rescue Client::RateLimitError, Client::TransientError, Client::InvalidResponseError => error
      back_off(error)
      nil
    end

    private

    def zone
      ActiveSupport::TimeZone[@account.timezone_name.to_s] || ActiveSupport::TimeZone["UTC"]
    end

    def insights_params(level, since, today)
      { level: level, fields: LEVELS.fetch(level) + METRICS, time_increment: 1,
        time_range: { since: since.iso8601, until: today.iso8601 }.to_json }
    end

    def finish(usage)
      @account.update!(sync_status: "ok", last_synced_at: @now, structure_synced_at: @now, insights_backfilled_at: @account.insights_backfilled_at || @now,
        retry_count: 0, last_error_code: nil, last_error_message: nil, next_sync_at: (usage >= HIGH_USAGE_PCT ? 15.minutes : 1.hour).since(@now))
    end

    # Exponential delay (1, 2, 4, ... minutes, capped at an hour), or what Meta asks for.
    def back_off(error)
      retries = @account.retry_count + 1
      delay = error.retry_after || [ BACKOFF_BASE * (2**(retries - 1)), MAX_BACKOFF.to_i ].min
      @account.update!(sync_status: error.is_a?(Client::RateLimitError) ? "rate_limited" : "failed", retry_count: retries, last_error_code: error.code,
        next_sync_at: delay.seconds.since(@now))
    end

    def upsert_rows(level, data)
      records = data.filter_map { |row| record_for(level, row) }
      return 0 if records.empty?

      DailyInsight.upsert_all(records, unique_by: UNIQUE_INDEX.fetch(level))
      records.size
    end

    def record_for(level, row)
      date = Date.iso8601(row["date_start"].to_s)
      campaign_id = row["campaign_id"].to_s
      return unless campaign_id.match?(ID_FORMAT)

      campaign = object(:campaign, campaign_id, row["campaign_name"])
      ad_set = ad = nil
      if level == "ad"
        return unless row["adset_id"].to_s.match?(ID_FORMAT) && row["ad_id"].to_s.match?(ID_FORMAT)

        ad_set = object(:ad_set, row["adset_id"].to_s, row["adset_name"], campaign: campaign)
        ad = object(:ad, row["ad_id"].to_s, row["ad_name"], campaign: campaign, ad_set: ad_set)
      end
      figures(row, date).merge(
        store_id: @store.id, ad_account_id: @account.id, level: level, date: date, currency: @account.currency, synced_at: @now,
        campaign_id: campaign.id, ad_set_id: ad_set&.id, ad_id: ad&.id,
        meta_campaign_id: campaign_id, meta_adset_id: ad_set&.meta_id, meta_ad_id: ad&.meta_id,
        campaign_name: row["campaign_name"].to_s.truncate(255).presence, adset_name: row["adset_name"].to_s.truncate(255).presence,
        ad_name: row["ad_name"].to_s.truncate(255).presence
      )
    rescue Date::Error
      nil
    end

    def figures(row, date)
      spend = decimal(row["spend"])
      actions = action_map(row["actions"])
      values = action_map(row["action_values"])
      purchases = PURCHASE_TYPES.find { |type| actions.key?(type) }
      value_type = PURCHASE_TYPES.find { |type| values.key?(type) }
      conversion_value = value_type ? values[value_type] : BigDecimal(0)
      quote = quote_for(date)
      {
        impressions: row["impressions"].to_i, reach: row["reach"].to_i, clicks: row["clicks"].to_i, spend: spend,
        ctr: decimal(row["ctr"], nil), cpc: decimal(row["cpc"], nil), cpm: decimal(row["cpm"], nil),
        conversions: purchases ? actions[purchases] : BigDecimal(0), conversion_value: conversion_value,
        roas: (spend.positive? && conversion_value.positive? ? (conversion_value / spend).round(4) : nil),
        raw_actions: actions.transform_values(&:to_s),
        spend_display: quote && (spend * quote.rate).round(4), display_currency: quote && @display_currency,
        fx_rate: quote&.rate, fx_date: quote&.date
      }
    end

    def quote_for(date)
      @quotes.fetch(date) { @quotes[date] = @fx.quote(@account.currency, @display_currency, on: date) }
    end

    # Rows saved while no rate was available get their conversion as soon as one is.
    def convert_missing
      DailyInsight.where(ad_account_id: @account.id, spend_display: nil).find_each do |insight|
        quote = quote_for(insight.date)
        next unless quote

        insight.update_columns(spend_display: (insight.spend * quote.rate).round(4), display_currency: @display_currency, fx_rate: quote.rate, fx_date: quote.date)
      end
    end

    def action_map(list)
      Array(list).each_with_object({}) do |entry, map|
        next unless entry.is_a?(Hash) && entry["action_type"].present?

        value = BigDecimal(entry["value"].to_s, exception: false)
        map[entry["action_type"].to_s] = value if value&.finite? && !value.negative?
      end
    end

    def decimal(value, default = BigDecimal(0))
      parsed = BigDecimal(value.to_s, exception: false)
      parsed&.finite? && !parsed.negative? ? parsed : default
    end

    # Names and parents of campaigns, ad sets and ads, learned from the insight rows themselves.
    def object(kind, meta_id, name, **parents)
      @objects[kind][meta_id] ||= begin
        record = { campaign: @account.campaigns, ad_set: @account.ad_sets, ad: @account.ads }.fetch(kind).find_or_initialize_by(meta_id: meta_id)
        record.store_id = @store.id if record.new_record?
        record.assign_attributes(name: name.presence&.truncate(255) || record.name, last_seen_at: @now, **parents)
        record.save! if record.changed?
        record
      end
    end
  end
end
