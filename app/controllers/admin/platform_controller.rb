# frozen_string_literal: true

module Admin
  # SaaS-owner home: cross-tenant metrics and store list (not store COD ops).
  class PlatformController < BaseController
    layout "admin_platform"
    before_action :require_super_admin!
    before_action :enter_platform_mode

    def show
      @stores = Store.order(:name).includes(:users, :invoices)
      @store_count = @stores.size
      @orders_scope = Order.all
      @orders_total = @orders_scope.count
      @orders_today = @orders_scope.where(created_at: Time.current.all_day).count
      @order_values = @orders_scope.where.not(status: "cancelled").group(:currency).sum(:total_cents).each_with_object(Hash.new(0)) do |(currency, cents), totals|
        totals[currency.to_s.upcase == "DH" ? "MAD" : currency.to_s.upcase] += cents
      end.sort.to_h
      @order_values = { "MAD" => 0 } if @order_values.empty?
      @staff_count = User.where.not(store_id: nil).count
      @pending_requests_count = AccessRequest.pending.count
    end

    private

    def enter_platform_mode
      session[:admin_mode] = "platform"
    end
  end
end
