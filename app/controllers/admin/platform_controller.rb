# frozen_string_literal: true

module Admin
  # SaaS-owner home: cross-tenant metrics and store list (not store COD ops).
  class PlatformController < BaseController
    layout "admin_platform"
    before_action :require_super_admin!
    before_action :enter_platform_mode

    def show
      @stores = Store.order(:name).includes(:users)
      @store_count = @stores.size
      @orders_scope = Order.all
      @orders_total = @orders_scope.count
      @orders_today = @orders_scope.where(created_at: Time.current.all_day).count
      @revenue_cents = @orders_scope.where.not(status: "cancelled").sum(:total_cents)
      @staff_count = User.where.not(store_id: nil).count
    end

    private

    def enter_platform_mode
      session[:admin_mode] = "platform"
    end
  end
end
