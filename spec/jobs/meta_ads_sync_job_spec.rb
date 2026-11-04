# frozen_string_literal: true

require "rails_helper"

RSpec.describe MetaAdsSyncJob do
  let(:store) { Store.create!(slug: "meta-job-#{SecureRandom.hex(5)}", name: "Synthetic", currency: "MAD") }
  let(:connection) { MetaAds::Connection.create!(store: store, access_token: "synthetic-job-token") }

  def account(id, **attributes)
    MetaAds::AdAccount.create!({ store: store, connection: connection, meta_ad_account_id: id, name: id, currency: "EUR", timezone_name: "UTC", account_status: 1,
      selected: true, next_sync_at: nil }.merge(attributes))
  end

  it "schedules one job per due, selected account of an active connection" do
    due = account("act_1")
    later = account("act_2", next_sync_at: 10.minutes.from_now)
    overdue = account("act_3", next_sync_at: 5.minutes.ago)
    unselected = account("act_4", selected: false)
    foreign_connection = MetaAds::Connection.create!(store: Store.create!(slug: "meta-job-b-#{SecureRandom.hex(5)}", name: "B", currency: "MAD"), access_token: "synthetic-b", status: "needs_reauthorization")
    foreign = account("act_5", store: foreign_connection.store, connection: foreign_connection)

    scheduled = []
    allow(described_class).to receive(:perform_later) { |id| scheduled << id }
    described_class.perform_now
    expect(scheduled).to match_array([ due.id, overdue.id ])
    expect(scheduled).not_to include(later.id, unselected.id, foreign.id)
  end

  it "syncs the account it is given and skips accounts that are no longer selected" do
    selected = account("act_1")
    sync = instance_double(MetaAds::InsightsSync, call: 3)
    expect(MetaAds::InsightsSync).to receive(:new).with(ad_account: selected).and_return(sync)
    described_class.perform_now(selected.id)

    selected.update!(selected: false)
    expect(MetaAds::InsightsSync).not_to receive(:new)
    described_class.perform_now(selected.id)
  end

  it "does not start a second sync while one started less than half an hour ago is still running" do
    running = account("act_1", sync_status: "running", last_attempt_at: 5.minutes.ago)
    allow(MetaAds::InsightsSync).to receive(:new).and_return(instance_double(MetaAds::InsightsSync, call: 0))
    described_class.perform_now(running.id)
    expect(MetaAds::InsightsSync).not_to have_received(:new)

    running.update!(last_attempt_at: 40.minutes.ago)
    described_class.perform_now(running.id)
    expect(MetaAds::InsightsSync).to have_received(:new).once
  end

  it "runs hourly from the schedule" do
    schedule = YAML.safe_load(ERB.new(Rails.root.join("config/schedule.yml").read).result)
    expect(schedule.fetch("meta_ads_sync")).to include("class" => "MetaAdsSyncJob", "cron" => "5 * * * *")
  end
end
