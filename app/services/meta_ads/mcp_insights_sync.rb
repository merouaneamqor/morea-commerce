# frozen_string_literal: true

module MetaAds
  # Experimental spend sync via Meta Ads MCP (`ads_get_ad_entities`) instead of Graph insights.
  # Enabled only when META_ADS_SYNC_VIA_MCP=1 and the connection has ads_mcp_management.
  # MCP metrics may arrive as display strings; unparsable spend rows are skipped (never invented).
  # Graph InsightsSync remains the default path in MetaAdsSyncJob.
  class McpInsightsSync
    BACKFILL_DAYS = InsightsSync::BACKFILL_DAYS
    UNIQUE_INDEX = InsightsSync::UNIQUE_INDEX
    ID_FORMAT = InsightsSync::ID_FORMAT
    BACKOFF_BASE = InsightsSync::BACKOFF_BASE
    MAX_BACKOFF = InsightsSync::MAX_BACKOFF

    LEVEL_CONFIG = {
      "campaign" => { mcp: "campaign", fields: %w[id name amount_spent impressions reach clicks ctr cpc cpm actions:omni_purchase] },
      "ad" => { mcp: "ad", fields: %w[id name campaign_id adset_id amount_spent impressions reach clicks ctr cpc cpm actions:omni_purchase] }
    }.freeze

    def initialize(ad_account:, transport: nil, fx: Fx.new, now: Time.current)
      @account = ad_account
      @transport = transport
      @fx = fx
      @now = now
      @quotes = {}
      @objects = { campaign: {}, ad_set: {}, ad: {} }
    end

    def call
      connection = @account.connection
      return unless @account.selected? && connection.active?
      return unless McpCapability.ready?(connection)

      @store = @account.store
      @display_currency = Fx.normalize(@store.currency)
      @account.update!(sync_status: "running", last_attempt_at: @now)
      client = McpClient.new(connection: connection, transport: @transport)
      today = zone.at(@now).to_date
      since = @account.insights_backfilled_at ? today - 1 : today - BACKFILL_DAYS
      written = 0
      LEVEL_CONFIG.each do |level, config|
        response = client.call_tool(
          "ads_get_ad_entities",
          ad_account_id: McpCapability.numeric_ad_account_id(@account.meta_ad_account_id),
          level: config[:mcp],
          fields: config[:fields],
          time_range: { since: since.iso8601, until: today.iso8601 }.to_json,
          time_increment: 1,
          limit: 1000
        )
        written += upsert_rows(level, extract_rows(response))
      end
      convert_missing
      ProductMatcher.call(store: @store)
      @account.update!(
        sync_status: "ok",
        last_synced_at: @now,
        insights_backfilled_at: @account.insights_backfilled_at || @now,
        retry_count: 0,
        last_error_code: nil,
        last_error_message: nil,
        next_sync_at: 1.hour.since(@now)
      )
      written
    rescue McpClient::AuthError, McpClient::PermissionError => error
      connection.mark_needs_reauthorization!(error.code)
      nil
    rescue McpClient::RateLimitError, McpClient::TransientError, McpClient::InvalidResponseError, McpClient::ToolError => error
      retries = @account.retry_count + 1
      delay = error.retry_after || [ BACKOFF_BASE * (2**(retries - 1)), MAX_BACKOFF.to_i ].min
      @account.update!(
        sync_status: error.is_a?(McpClient::RateLimitError) ? "rate_limited" : "failed",
        retry_count: retries,
        last_error_code: error.code,
        next_sync_at: delay.seconds.since(@now)
      )
      nil
    end

    private

    def zone
      ActiveSupport::TimeZone[@account.timezone_name.to_s] || ActiveSupport::TimeZone["UTC"]
    end

    def extract_rows(response)
      payload = response.tool_json
      case payload
      when Array then payload
      when Hash then Array(payload["data"] || payload["entities"] || payload["results"] || payload["rows"])
      else []
      end
    end

    def upsert_rows(level, data)
      records = Array(data).filter_map { |row| record_for(level, row) if row.is_a?(Hash) }
      return 0 if records.empty?

      DailyInsight.upsert_all(records, unique_by: UNIQUE_INDEX.fetch(level))
      records.size
    end

    def record_for(level, row)
      date = parse_date(row)
      return unless date

      campaign_meta = (row["campaign_id"] || (level == "campaign" ? row["id"] : nil)).to_s
      return unless campaign_meta.match?(ID_FORMAT)

      campaign = object(:campaign, campaign_meta, row["campaign_name"] || (level == "campaign" ? row["name"] : nil))
      ad_set = ad = nil
      if level == "ad"
        ad_meta = row["id"].to_s
        adset_meta = row["adset_id"].to_s
        return unless ad_meta.match?(ID_FORMAT) && adset_meta.match?(ID_FORMAT)

        ad_set = object(:ad_set, adset_meta, row["adset_name"], campaign: campaign)
        ad = object(:ad, ad_meta, row["name"], campaign: campaign, ad_set: ad_set)
      end

      spend = parse_decimal(row["amount_spent"] || row["spend"])
      return if spend.nil?

      purchases = parse_decimal(row["actions:omni_purchase"] || row["omni_purchase"]) || BigDecimal(0)
      quote = quote_for(date)
      {
        store_id: @store.id,
        ad_account_id: @account.id,
        level: level,
        date: date,
        currency: @account.currency,
        synced_at: @now,
        created_at: @now,
        updated_at: @now,
        campaign_id: campaign.id,
        ad_set_id: ad_set&.id,
        ad_id: ad&.id,
        meta_campaign_id: campaign_meta,
        meta_adset_id: ad_set&.meta_id,
        meta_ad_id: ad&.meta_id,
        campaign_name: (row["campaign_name"] || (level == "campaign" ? row["name"] : nil)).to_s.truncate(255).presence,
        adset_name: row["adset_name"].to_s.truncate(255).presence,
        ad_name: (level == "ad" ? row["name"] : nil).to_s.truncate(255).presence,
        impressions: parse_int(row["impressions"]) || 0,
        reach: parse_int(row["reach"]) || 0,
        clicks: parse_int(row["clicks"]) || 0,
        spend: spend,
        ctr: parse_decimal(row["ctr"], allow_nil: true),
        cpc: parse_decimal(row["cpc"], allow_nil: true),
        cpm: parse_decimal(row["cpm"], allow_nil: true),
        conversions: purchases,
        conversion_value: BigDecimal(0),
        roas: nil,
        raw_actions: purchases.positive? ? { "omni_purchase" => purchases.to_s } : {},
        spend_display: quote && (spend * quote.rate).round(4),
        display_currency: quote && @display_currency,
        fx_rate: quote&.rate,
        fx_date: quote&.date
      }
    end

    def object(kind, meta_id, name, **parents)
      @objects[kind][meta_id] ||= begin
        record = { campaign: @account.campaigns, ad_set: @account.ad_sets, ad: @account.ads }.fetch(kind).find_or_initialize_by(meta_id: meta_id)
        record.store_id = @store.id if record.new_record?
        record.assign_attributes(name: name.presence&.truncate(255) || record.name, last_seen_at: @now, **parents)
        record.save! if record.changed?
        record
      end
    end

    def quote_for(date)
      @quotes.fetch(date) { @quotes[date] = @fx.quote(@account.currency, @display_currency, on: date) }
    end

    def convert_missing
      DailyInsight.where(ad_account_id: @account.id, spend_display: nil).find_each do |insight|
        quote = quote_for(insight.date)
        next unless quote

        insight.update_columns(
          spend_display: (insight.spend * quote.rate).round(4),
          display_currency: @display_currency,
          fx_rate: quote.rate,
          fx_date: quote.date
        )
      end
    end

    def parse_date(row)
      raw = row["date_start"] || row["date"] || row["day"]
      Date.iso8601(raw.to_s) if raw.present?
    rescue Date::Error, ArgumentError
      nil
    end

    def parse_decimal(value, allow_nil: false)
      return if value.nil? && allow_nil
      return value.to_d if value.is_a?(Numeric)

      text = value.to_s.strip
      return if text.blank? || text.match?(/not available/i)

      cleaned = text.gsub(/[^\d,.\-]/, "")
      if cleaned.include?(",") && cleaned.include?(".")
        cleaned = cleaned.gsub(",", "")
      elsif cleaned.count(",") == 1 && cleaned.count(".") == 0
        cleaned = cleaned.tr(",", ".")
      end
      if cleaned.count(".") > 1
        parts = cleaned.split(".")
        cleaned = parts[0..-2].join + "." + parts.last
      end
      parsed = BigDecimal(cleaned, exception: false)
      return if parsed.nil? || !parsed.finite? || parsed.negative?
      parsed
    end

    def parse_int(value)
      return if value.nil?
      return value.to_i if value.is_a?(Numeric)

      Integer(value.to_s.gsub(/[^\d\-]/, ""), exception: false)
    end
  end
end
