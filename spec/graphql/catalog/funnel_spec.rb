# frozen_string_literal: true

require "rails_helper"

RSpec.describe Catalog::Funnel do
  let(:store) { Store.create!(slug: "cf-#{SecureRandom.hex(4)}", name: "Catalog Funnel", currency: "MAD", storefront_enabled: true) }
  let(:now) { Time.zone.parse("2026-11-15 12:00:00") }

  def visit!(stage:, source: "facebook", path: "/en/", hours_ago: 1)
    store.storefront_visits.create!(
      token: SecureRandom.hex(8),
      utm_source: source,
      funnel_stage: stage,
      landing_path: path,
      landed_at: now - hours_ago.hours,
      last_seen_at: now - hours_ago.hours
    )
  end

  around do |example|
    travel_to(now) { example.run }
  end

  it "returns a date-bounded aggregate without raw visit ids" do
    visit!(stage: "landed", source: "direct", path: "/en/")
    visit!(stage: "ordered", source: "facebook", path: "/en/products/x")

    summary = described_class.summary(store, since: "2026-11-01", until_on: "2026-11-15", sources_limit: 10, landings_limit: 5)

    expect(summary.from).to eq(Date.new(2026, 11, 1))
    expect(summary.to).to eq(Date.new(2026, 11, 15))
    expect(summary.total_visits).to eq(2)
    expect(summary.stages.map(&:key)).to eq(StorefrontVisit::STAGES)
    expect(summary.sources.map(&:label)).to include("meta", "direct")
    expect(summary.landings.map(&:path)).to include("/en/products/x")
    expect(summary.sources_limit).to eq(10)
    expect(summary.landings_limit).to eq(5)
    expect(summary.to_h.keys).not_to include(:visits, :events)
  end

  it "rejects windows longer than 366 days" do
    expect {
      described_class.summary(store, since: "2025-01-01", until_on: "2026-11-15")
    }.to raise_error(Catalog::Analytics::Error, /366/)
  end

  it "clamps source and landing limits" do
    summary = described_class.summary(store, sources_limit: 999, landings_limit: 0)
    expect(summary.sources_limit).to eq(50)
    expect(summary.landings_limit).to eq(10)
  end

  it "issues a bounded number of store-scoped queries" do
    3.times { |i| visit!(stage: "landed", source: "s#{i}", path: "/p/#{i}") }

    queries = []
    callback = lambda do |_name, _start, _finish, _id, payload|
      sql = payload[:sql].to_s
      next unless sql.match?(/storefront_visits|FROM "orders"/i)

      queries << sql
    end

    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      described_class.summary(store, since: "2026-11-01", until_on: "2026-11-15", sources_limit: 5, landings_limit: 5)
    end

    visit_queries = queries.select { |sql| sql.include?("storefront_visits") }
    expect(visit_queries).not_to be_empty
    expect(visit_queries.size).to be <= 8
    expect(visit_queries.join("\n")).to match(/store_id/i)
    expect(visit_queries.join("\n")).not_to match(/SELECT ["`]?storefront_visits["`]?\.\*/i)
    expect(visit_queries.any? { |sql| sql.match?(/LIMIT/i) }).to eq(true)
  end
end
