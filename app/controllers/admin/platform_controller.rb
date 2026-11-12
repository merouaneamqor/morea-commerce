# frozen_string_literal: true

module Admin
  # SaaS-owner home: action queue, cross-tenant metrics, and workspace list.
  class PlatformController < BaseController
    layout "admin_platform"
    before_action :require_super_admin!
    before_action :enter_platform_mode

    def show
      @summary = Platform::DashboardSummary.new
      @action_queue = Platform::ActionQueue.new
      @stores = Store.order(:name).includes(:users, :invoices)
      @store_count = @summary.stores_count
      @pending_requests_count = @summary.pending_requests_count
      @orders_today = @summary.orders_today_count
      @staff_count = User.where.not(store_id: nil).count
      @orders_scope = Order.all
      @orders_total = @orders_scope.count
      @order_values = @orders_scope.where.not(status: "cancelled").group(:currency).sum(:total_cents).each_with_object(Hash.new(0)) do |(currency, cents), totals|
        totals[currency.to_s.upcase == "DH" ? "MAD" : currency.to_s.upcase] += cents
      end.sort.to_h
      @order_values = { "MAD" => 0 } if @order_values.empty?
    end

    private

    def enter_platform_mode
      session[:admin_mode] = "platform"
    end
  end
end
