module Admin
  class DashboardController < BaseController
    def show
      return redirect_to(admin_platform_path) if super_admin? && session[:admin_mode] != "store"
      return redirect_to(admin_platform_path) if super_admin? && !current_store
      return head(:not_found) unless current_store

      @stats = Seller::DashboardStats.new(store: current_store, period: params[:period]).to_h
    end
  end
end
