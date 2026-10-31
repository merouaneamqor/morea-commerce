# frozen_string_literal: true

require "rails_helper"
require "erb"
require "yaml"

RSpec.describe "Integration polling schedules" do
  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("SENDIT_POLL_CRON", "*/15 * * * *").and_return("*/15 * * * *")
    allow(ENV).to receive(:fetch).with("SHOPIFY_SYNC_CRON", "*/10 * * * *").and_return("*/10 * * * *")
  end

  def schedules(sendit_external: nil, shopify_external: nil, retention_external: nil)
    allow(ENV).to receive(:[]).with("SENDIT_EXTERNAL_CRON").and_return(sendit_external)
    allow(ENV).to receive(:[]).with("SHOPIFY_EXTERNAL_CRON").and_return(shopify_external)
    allow(ENV).to receive(:[]).with("SEALLO_RETENTION_EXTERNAL_CRON").and_return(retention_external)
    YAML.safe_load(ERB.new(Rails.root.join("config/schedule.yml").read).result)
  end

  it "schedules both integrations and the Seallo retention sweep by default" do
    result = schedules
    expect(result.keys).to contain_exactly("sendit_poll", "shopify_orders_sync", "seallo_retention")
    expect(result.fetch("sendit_poll")).to include("cron" => "*/15 * * * *", "class" => "SenditPollJob", "active_job" => true)
    expect(result.fetch("shopify_orders_sync")).to include("cron" => "*/10 * * * *", "class" => "ShopifyOrdersSyncJob", "queue" => "default", "active_job" => true)
  end

  it "keeps Shopify polling when Sendit uses an external runner" do
    expect(schedules(sendit_external: "1").keys).to contain_exactly("shopify_orders_sync", "seallo_retention")
  end

  it "keeps Sendit polling when Shopify uses an external runner" do
    expect(schedules(shopify_external: "1").keys).to contain_exactly("sendit_poll", "seallo_retention")
  end

  it "keeps only the retention sweep when both integrations use external runners" do
    expect(schedules(sendit_external: "1", shopify_external: "1").keys).to eq([ "seallo_retention" ])
  end

  it "renders an empty schedule when every job uses an external runner" do
    expect(schedules(sendit_external: "1", shopify_external: "1", retention_external: "1")).to eq({})
  end

  it "retains configurable polling intervals" do
    allow(ENV).to receive(:fetch).with("SENDIT_POLL_CRON", "*/15 * * * *").and_return("*/20 * * * *")
    allow(ENV).to receive(:fetch).with("SHOPIFY_SYNC_CRON", "*/10 * * * *").and_return("*/5 * * * *")
    result = schedules
    expect(result.fetch("sendit_poll").fetch("cron")).to eq("*/20 * * * *")
    expect(result.fetch("shopify_orders_sync").fetch("cron")).to eq("*/5 * * * *")
  end
end
