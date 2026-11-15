# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Performance vitals beacon", type: :request do
  it "accepts a JSON LCP beacon and rejects unknown metrics" do
    expect(Rails.logger).to receive(:info).with(a_string_including("\"event\":\"web_vital\"", "\"name\":\"LCP\""))

    post "/performance/vitals",
      params: { name: "LCP", value: 1800.5, path: "/en", locale: "en", rating: "good" }.to_json,
      headers: { "CONTENT_TYPE" => "application/json" }

    expect(response).to have_http_status(:no_content)

    post "/performance/vitals",
      params: { name: "HACK", value: 1 }.to_json,
      headers: { "CONTENT_TYPE" => "application/json" }

    expect(response).to have_http_status(:bad_request)
  end
end
