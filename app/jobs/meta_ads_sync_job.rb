# frozen_string_literal: true

# Hourly: syncs every selected Meta ad account that is due (yesterday and today, plus a 30 day backfill the first
# time). Called without an argument it only schedules one job per due account; each account then runs on its own,
# so one account's rate limit or error never delays the others. Backoff lives in next_sync_at on the account.
class MetaAdsSyncJob < ApplicationJob
  queue_as :default

  def perform(ad_account_id = nil)
    return schedule_due if ad_account_id.nil?

    account = MetaAds::AdAccount.selected.find_by(id: ad_account_id)
    return unless account

    # Skip a run another worker started less than half an hour ago.
    return if account.sync_status == "running" && account.last_attempt_at.present? && account.last_attempt_at > 30.minutes.ago

    MetaAds::InsightsSync.new(ad_account: account).call
  end

  private

  def schedule_due
    MetaAds::AdAccount.selected.joins(:connection).where(meta_ads_connections: { status: "active" })
      .where("meta_ads_ad_accounts.next_sync_at IS NULL OR meta_ads_ad_accounts.next_sync_at <= ?", Time.current).pluck(:id)
      .each { |id| self.class.perform_later(id) }
  end
end
