# frozen_string_literal: true

module Platform
  # Cross-workspace overview for authenticated super admins only. These are
  # platform invoice receipts, not merchant sales or COD collections.
  class DashboardSummary
    ZONE = "Africa/Casablanca"
    LIST_LIMIT = 10

    attr_reader :now, :stores_count, :storefronts_count, :active_users_count,
      :pending_requests_count, :orders_today_count, :orders_30_days_count,
      :paid_this_month_cents, :outstanding_cents, :overdue_count, :overdue_cents,
      :recent_stores, :overdue_invoices

    def initialize(now: Time.current)
      @now = now.in_time_zone(ZONE)
      summarize_workspaces
      summarize_orders
      summarize_billing
    end

    private

    def summarize_workspaces
      storefront_counts = Store.group(:storefront_enabled).count
      @stores_count = storefront_counts.values.sum
      @storefronts_count = storefront_counts.fetch(true, 0)
      @active_users_count = User.active.count
      @pending_requests_count = AccessRequest.pending.count
      @recent_stores = Store.order(created_at: :desc, id: :desc).limit(LIST_LIMIT).to_a
    end

    def summarize_orders
      @orders_today_count = Order.where(created_at: now.beginning_of_day..now).count
      starts_at = (now.to_date - 29).in_time_zone(ZONE).beginning_of_day
      @orders_30_days_count = Order.where(created_at: starts_at..now).count
    end

    def summarize_billing
      @paid_this_month_cents = Invoice.where(status: "paid", paid_at: now.beginning_of_month..now).sum(:amount_cents)
      issued = Invoice.open_issued
      @outstanding_cents = issued.sum(:amount_cents)
      overdue = issued.where("due_on < ?", now.to_date)
      @overdue_count = overdue.count
      @overdue_cents = overdue.sum(:amount_cents)
      @overdue_invoices = overdue.includes(:store).order(:due_on, :id).limit(LIST_LIMIT).to_a
    end
  end
end
