# frozen_string_literal: true

module MetaAds
  # Pulls campaign / ad set / ad structure (status, objective, budgets) for one selected ad account.
  # Read-only Marketing API fields available with ads_read. Budgets stay in the account currency.
  # Objects Meta stops returning keep their last known row; last_seen_at marks the freshest sync.
  class StructureSync
    ID_FORMAT = /\A\d{1,25}\z/
    CAMPAIGN_FIELDS = %w[id name status effective_status objective daily_budget lifetime_budget budget_remaining spend_cap updated_time].freeze
    AD_SET_FIELDS = %w[id name campaign_id status effective_status daily_budget lifetime_budget budget_remaining updated_time].freeze
    AD_FIELDS = %w[id name adset_id campaign_id status effective_status updated_time].freeze
    # Keep paused and in-review inventory visible; drop deleted/archived noise from the follow-up list.
    EFFECTIVE_STATUSES = %w[ACTIVE PAUSED PENDING_REVIEW DISAPPROVED PREAPPROVED PENDING_BILLING_INFO CAMPAIGN_PAUSED ADSET_PAUSED IN_PROCESS WITH_ISSUES].freeze

    def initialize(ad_account:, client:, now: Time.current)
      @account = ad_account
      @client = client
      @now = now
      @usage = 0
      @campaigns = {}
      @ad_sets = {}
    end

    # Returns the peak usage percentage seen while reading structure endpoints.
    def call
      sync_collection("campaigns", CAMPAIGN_FIELDS) { |row| upsert_campaign(row) }
      sync_collection("adsets", AD_SET_FIELDS) { |row| upsert_ad_set(row) }
      sync_collection("ads", AD_FIELDS) { |row| upsert_ad(row) }
      @usage
    end

    private

    def sync_collection(edge, fields)
      response = @client.collect("#{@account.meta_ad_account_id}/#{edge}",
        fields: fields, filtering: [ { field: "effective_status", operator: "IN", value: EFFECTIVE_STATUSES } ].to_json)
      @usage = [ @usage, response.usage_pct ].max
      response.data.each { |row| yield row if row.is_a?(Hash) }
    end

    def upsert_campaign(row)
      meta_id = row["id"].to_s
      return unless meta_id.match?(ID_FORMAT)

      record = @account.campaigns.find_or_initialize_by(meta_id: meta_id)
      record.store_id = @account.store_id if record.new_record?
      record.assign_attributes(
        name: truncate(row["name"]) || record.name,
        status: truncate(row["status"], 40),
        effective_status: truncate(row["effective_status"], 40),
        objective: truncate(row["objective"], 80),
        daily_budget: Money.from_minor(row["daily_budget"], currency: @account.currency),
        lifetime_budget: Money.from_minor(row["lifetime_budget"], currency: @account.currency),
        budget_remaining: Money.from_minor(row["budget_remaining"], currency: @account.currency),
        spend_cap: Money.from_minor(row["spend_cap"], currency: @account.currency),
        meta_updated_at: parse_time(row["updated_time"]) || record.meta_updated_at,
        last_seen_at: @now,
        raw: row.slice(*CAMPAIGN_FIELDS)
      )
      record.save! if record.changed?
      @campaigns[meta_id] = record
    end

    def upsert_ad_set(row)
      meta_id = row["id"].to_s
      campaign_meta = row["campaign_id"].to_s
      return unless meta_id.match?(ID_FORMAT) && campaign_meta.match?(ID_FORMAT)

      campaign = @campaigns[campaign_meta] || @account.campaigns.find_by(meta_id: campaign_meta)
      return unless campaign

      record = @account.ad_sets.find_or_initialize_by(meta_id: meta_id)
      record.store_id = @account.store_id if record.new_record?
      record.assign_attributes(
        campaign: campaign,
        name: truncate(row["name"]) || record.name,
        status: truncate(row["status"], 40),
        effective_status: truncate(row["effective_status"], 40),
        daily_budget: Money.from_minor(row["daily_budget"], currency: @account.currency),
        lifetime_budget: Money.from_minor(row["lifetime_budget"], currency: @account.currency),
        budget_remaining: Money.from_minor(row["budget_remaining"], currency: @account.currency),
        meta_updated_at: parse_time(row["updated_time"]) || record.meta_updated_at,
        last_seen_at: @now,
        raw: row.slice(*AD_SET_FIELDS)
      )
      record.save! if record.changed?
      @ad_sets[meta_id] = record
    end

    def upsert_ad(row)
      meta_id = row["id"].to_s
      ad_set_meta = row["adset_id"].to_s
      campaign_meta = row["campaign_id"].to_s
      return unless meta_id.match?(ID_FORMAT) && ad_set_meta.match?(ID_FORMAT) && campaign_meta.match?(ID_FORMAT)

      campaign = @campaigns[campaign_meta] || @account.campaigns.find_by(meta_id: campaign_meta)
      ad_set = @ad_sets[ad_set_meta] || @account.ad_sets.find_by(meta_id: ad_set_meta)
      return unless campaign && ad_set

      record = @account.ads.find_or_initialize_by(meta_id: meta_id)
      record.store_id = @account.store_id if record.new_record?
      record.assign_attributes(
        campaign: campaign,
        ad_set: ad_set,
        name: truncate(row["name"]) || record.name,
        status: truncate(row["status"], 40),
        effective_status: truncate(row["effective_status"], 40),
        meta_updated_at: parse_time(row["updated_time"]) || record.meta_updated_at,
        last_seen_at: @now,
        raw: row.slice(*AD_FIELDS)
      )
      record.save! if record.changed?
    end

    def truncate(value, length = 255)
      value.to_s.truncate(length).presence
    end

    def parse_time(value)
      return if value.blank?

      Time.iso8601(value.to_s)
    rescue ArgumentError
      nil
    end
  end
end
