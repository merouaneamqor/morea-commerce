# frozen_string_literal: true

require "rails_helper"

RSpec.describe Attribution::Params do
  it "reads UTM and click ids from a params hash" do
    expect(described_class.from_hash(
      "utm_source" => "facebook",
      "utm_campaign" => "120200000000001",
      "fbclid" => "Iw.abc",
      "gclid" => "Cj.xyz",
      "ttclid" => "E.ttt",
      "ignored" => "no"
    )).to eq(
      utm_source: "facebook",
      utm_campaign: "120200000000001",
      fbclid: "Iw.abc",
      gclid: "Cj.xyz",
      ttclid: "E.ttt"
    )
  end

  it "keeps first-touch values and fills Meta ids from Facebook macros" do
    first = described_class.merge_first_touch({}, {
      "utm_source" => "facebook",
      "utm_campaign" => "120200000000001",
      "utm_term" => "120200000000002",
      "utm_content" => "120200000000003",
      "landing_path" => "/en/?utm_source=facebook"
    })
    second = described_class.merge_first_touch(first, {
      "utm_source" => "google",
      "gclid" => "later-click",
      "landing_path" => "/en/other"
    })

    expect(second).to include(
      utm_source: "facebook",
      utm_campaign: "120200000000001",
      gclid: "later-click",
      landing_path: "/en/?utm_source=facebook",
      meta_campaign_id: "120200000000001",
      meta_adset_id: "120200000000002",
      meta_ad_id: "120200000000003"
    )
  end
end
