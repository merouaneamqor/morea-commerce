module Admin
  class DashboardController < BaseController
    include DateRangeSelection

    def show
      return redirect_to(admin_platform_path) if super_admin? && session[:admin_mode] != "store"
      return redirect_to(admin_platform_path) if super_admin? && !current_store
      return head(:not_found) unless current_store

      @date_range = selected_date_range(scope: "dashboard", default: "last_7", **legacy_period)
      @stats = Seller::DashboardStats.new(store: current_store, range: @date_range).to_h
      @milestones = Seller::RevenueMilestones.new(store: current_store) if current_user.show_milestones
    end

    # Switch the milestones bar on or off for the signed-in person (?show=1 or 0).
    def milestones
      return head(:not_found) unless current_store

      current_user.update!(show_milestones: params[:show] == "1")
      redirect_back_or_to seller_dashboard_path, status: :see_other
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
