module Admin
  # "Mes statistiques": one person's own confirmed/delivered orders and pay.
  class MyStatsController < BaseController
    before_action :require_store_context!

    PERIODS = %w[today week month].freeze

    def show
      @period = PERIODS.include?(params[:period]) ? params[:period] : "month"
      @range = range_for(@period)
      earnings = Team::AgentEarnings.new(store: current_store, range: @range)
      @summary = earnings.summary_for(current_user)
      @by_day = earnings.confirmed_by_day(current_user)
      @week_days = (6.days.ago.to_date..Date.current).to_a
    end

    private

    def require_store_context!
      head :not_found unless current_store
    end

    def range_for(period)
      now = Time.current
      case period
      when "today" then now.beginning_of_day..now
      when "week" then (now.beginning_of_day - 6.days)..now
      else now.beginning_of_month..now
      end
    end
  end
end
