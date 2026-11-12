module Admin
  class DashboardController < BaseController
    include DateRangeSelection

    def show
      return redirect_to(admin_platform_path) if super_admin? && session[:admin_mode] != "store"
      return redirect_to(admin_platform_path) if super_admin? && !current_store
      return head(:not_found) unless current_store

      @date_range = selected_date_range(scope: "dashboard", default: "last_7", **legacy_period)
      @stats = Seller::DashboardStats.new(store: current_store, range: @date_range).to_h
      @milestones = Seller::RevenueMilestones.new(store: current_store)
    end

    private

    # An older link with ?period=7d opens the matching range.
    def legacy_period
      key = Seller::DashboardStats::LEGACY_PERIODS[params[:period].to_s]
      range = DateRange.preset(key) if key && params[:from].blank?
      range ? range.to_param : {}
    end
  end
end
