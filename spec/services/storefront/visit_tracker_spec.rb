# frozen_string_literal: true

require "rails_helper"

RSpec.describe Storefront::VisitTracker do
  let(:store) { Store.create!(slug: "vt-#{SecureRandom.hex(4)}", name: "Visit Tracker", currency: "MAD", storefront_enabled: true) }
  let(:cookies) { {} }
  let(:session) { {} }
  let(:tracker) { described_class.new(store: store, cookies: cookies, session: session, measurement_allowed: true) }

  def request_with(query)
    params = Rack::Utils.parse_query(query)
    instance_double(
      ActionDispatch::Request,
      query_parameters: params,
      fullpath: "/en/?#{query}",
      referer: "https://www.facebook.com/"
    )
  end

  it "stores first-touch attribution in the session even before a visit row exists" do
    tracker.capture_attribution!(request_with("utm_source=facebook&utm_campaign=120200000000001&fbclid=Iw.1"))
    expect(session[:storefront_attribution]).to include(
      "utm_source" => "facebook",
      "utm_campaign" => "120200000000001",
      "fbclid" => "Iw.1",
      "meta_campaign_id" => "120200000000001"
    )
  end

  it "records funnel events and advances the visit stage when measurement is allowed" do
    tracker.capture_attribution!(request_with("utm_source=tiktok&ttclid=E.1"))
    visit = tracker.record!(stage: "product_viewed", path: "/en/products/shoes")
    expect(visit).to have_attributes(funnel_stage: "product_viewed", utm_source: "tiktok", ttclid: "E.1")
    expect(visit.storefront_funnel_events.order(:id).pluck(:name)).to eq(%w[landed product_viewed])

    tracker.record!(stage: "added_to_cart", path: "/en/cart")
    expect(visit.reload.funnel_stage).to eq("added_to_cart")
  end

  it "does not write visit rows when measurement is denied" do
    denied = described_class.new(store: store, cookies: cookies, session: session, measurement_allowed: false)
    denied.capture_attribution!(request_with("utm_source=facebook&utm_campaign=120200000000001"))
    expect(denied.record!(stage: "landed", path: "/en/")).to be_nil
    expect(store.storefront_visits).to be_empty
    expect(session[:storefront_attribution]["utm_source"]).to eq("facebook")
  end
end
