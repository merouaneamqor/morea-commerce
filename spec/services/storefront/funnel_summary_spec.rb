# frozen_string_literal: true

require "rails_helper"

RSpec.describe Storefront::FunnelSummary do
  let(:store) { Store.create!(slug: "fs-#{SecureRandom.hex(4)}", name: "Funnel Summary", currency: "MAD", storefront_enabled: true) }
  let(:range) { 7.days.ago..Time.current }
  let(:now) { Time.current }

  def visit!(stage:, source: "facebook", hours_ago: 1)
    store.storefront_visits.create!(
      token: SecureRandom.hex(8),
      utm_source: source,
      funnel_stage: stage,
      landing_path: "/en/?utm_source=#{source}",
      landed_at: now - hours_ago.hours,
      last_seen_at: now - hours_ago.hours
    )
  end

  it "builds cumulative funnel stages, sources and abandoned carts" do
    visit!(stage: "landed", source: "direct")
    visit!(stage: "product_viewed", source: "facebook")
    visit!(stage: "checkout_started", source: "facebook", hours_ago: 0)
    visit!(stage: "ordered", source: "tiktok")
    abandoned = visit!(stage: "added_to_cart", source: "google", hours_ago: 2)
    abandoned.update!(last_seen_at: 2.hours.ago)

    summary = described_class.new(store: store, range: range)
    stages = summary.stages.index_by(&:key)
    expect(stages["landed"].visits).to eq(5)
    expect(stages["product_viewed"].visits).to eq(4)
    expect(stages["added_to_cart"].visits).to eq(3)
    expect(stages["checkout_started"].visits).to eq(2)
    expect(stages["ordered"].visits).to eq(1)
    expect(summary.abandoned_visits).to eq(1)

    facebook = summary.sources.find { |row| row.label == "meta" }
    expect(facebook).to have_attributes(visits: 2, checkouts: 1, orders: 0)

    landings = summary.top_landings(limit: 5)
    expect(landings.map(&:path)).to include("/en/?utm_source=facebook")
    expect(landings.size).to be <= 5
  end

  it "aggregates sources in SQL and respects the sources limit" do
    12.times { |i| visit!(stage: "landed", source: "src#{i}") }
    summary = described_class.new(store: store, range: range, sources_limit: 5)
    expect(summary.sources.size).to eq(5)
    expect(summary.as_payload[:sources_limit]).to eq(5)
  end
end
