# frozen_string_literal: true

module Admin
  # First-party visit sources and storefront funnel drop-offs for the current store.
  class FunnelController < BaseController
    include DateRangeSelection

    def show
      @date_range = selected_date_range(scope: "funnel", default: "last_30")
      @summary = Storefront::FunnelSummary.new(store: current_store, range: @date_range)
    end
  end
end
