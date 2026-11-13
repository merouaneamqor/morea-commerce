# frozen_string_literal: true

module Admin
  class DeliveryController < BaseController
    include DateRangeSelection

    def show
      return redirect_to(admin_platform_path) if super_admin? && !current_store
      return head(:not_found) unless current_store

      @date_range = selected_date_range(scope: "delivery", default: "last_30", **legacy_dates)
      @delivery = DeliverySummary.new(store: current_store, start_date: @date_range.from.iso8601, end_date: @date_range.to.iso8601,
        status: params[:status], query: params[:q])
      # The summary keeps at most a year; show the days it really used.
      used = DateRange.build(@delivery.start_date, @delivery.end_date)
      if used && used != @date_range
        @date_range = used
        @date_range_preset = nil
      end
    end

    private

    # An older link with ?start_date=&end_date= still works.
    def legacy_dates
      return {} unless params[:from].blank? && (params[:start_date].present? || params[:end_date].present?)

      { from: params[:start_date], to: params[:end_date] }
    end
  end
end
