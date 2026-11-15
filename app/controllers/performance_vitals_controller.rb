# frozen_string_literal: true

# Accepts browser Core Web Vitals beacons. Logs structured metrics only; no customer PII.
class PerformanceVitalsController < ActionController::Base
  protect_from_forgery with: :null_session

  METRICS = %w[LCP CLS INP FCP TTFB].freeze

  def create
    payload = beacon_payload
    name = payload["name"].to_s
    return head :bad_request unless METRICS.include?(name)

    value = Float(payload["value"], exception: false)
    return head :bad_request if value.nil? || value.negative? || value > 60_000

    Rails.logger.info({
      event: "web_vital",
      name: name,
      value: value.round(3),
      id: payload["id"].to_s.first(64),
      rating: payload["rating"].to_s.first(16),
      path: payload["path"].to_s.first(200),
      locale: payload["locale"].to_s.first(8),
      navigation: payload["navigationType"].to_s.first(32)
    }.to_json)

    head :no_content
  end

  private

  def beacon_payload
    if request.media_type == "application/json"
      JSON.parse(request.raw_post)
    else
      params.to_unsafe_h
    end
  rescue JSON::ParserError
    {}
  end
end
