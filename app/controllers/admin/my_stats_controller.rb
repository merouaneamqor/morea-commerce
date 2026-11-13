module Admin
  # "Mes statistiques": one person's own confirmed/delivered orders and pay.
  class MyStatsController < BaseController
    include DateRangeSelection

    before_action :require_store_context!

    # Older links used ?period=today|week|month; they still open the matching range.
    LEGACY_PERIODS = { "today" => "today", "week" => "last_7", "month" => "this_month" }.freeze

    def show
      @date_range = selected_date_range(scope: "my_stats", default: "this_month", **legacy_period)
      @range = @date_range.time_range
      earnings = Team::AgentEarnings.new(store: current_store, range: @range)
      @summary = earnings.summary_for(current_user)
      @by_day = earnings.confirmed_by_day(current_user)
      @chart_days = @date_range.dates.to_a.last(31) # one bar per day, the last 31 at most
    end

    private

    def require_store_context!
      head :not_found unless current_store
    end

    def legacy_period
      key = LEGACY_PERIODS[params[:period].to_s]
      range = DateRange.preset(key) if key && params[:from].blank?
      range ? range.to_param : {}
    end
  end
end
