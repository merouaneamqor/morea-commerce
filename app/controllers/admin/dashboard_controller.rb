module Admin
  class DashboardController < BaseController
    def show
      return redirect_to(admin_platform_path) if super_admin? && session[:admin_mode] != "store"
      return redirect_to(admin_platform_path) if super_admin? && !current_store
      return head(:not_found) unless current_store

      now = Time.current
      @dashboard = DashboardSummary.new(store: current_store, period: params[:period], now: now)
      @overview = OverviewMetrics.new(store: current_store, period: @dashboard.period, now: now)
    end
  end
end
