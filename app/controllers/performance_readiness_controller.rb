# frozen_string_literal: true

class PerformanceReadinessController < ActionController::Base
  def show
    response.headers["Cache-Control"] = "no-store"
    expected = ENV.fetch("PERF_TARGET_TOKEN", "")
    supplied = request.headers["X-Morea-Perf-Token"].to_s
    return head :not_found unless Rails.env.test? && expected.size >= 24 &&
      ActiveSupport::SecurityUtils.secure_compare(expected, supplied)

    store = Store.find_by_host(request.host)
    return head :service_unavailable unless store&.slug == ENV.fetch("DEFAULT_STORE_SLUG", "morea") &&
      store.name == "Synthetic Performance Store" && !store.sendit_configured? && !store.pixels_configured? &&
      store.discord_orders_webhook_url.blank? &&
      store.products.active.exists?(slug: "perf-product") && store.collections.published.exists?(slug: "perf-collection") &&
      ActiveJob::Base.queue_adapter.is_a?(ActiveJob::QueueAdapters::TestAdapter)

    message = ENV["PERF_SYNTHETIC_ORDERS"] == "yes" ? "synthetic-orders-ready" : "performance-ready"
    render plain: message
  end
end
