# frozen_string_literal: true

module Admin
  # Cross-workspace subscription billing (plans, renewals, issued and overdue invoices).
  # Merchant order revenue is intentionally excluded.
  class PlatformBillingController < BaseController
    layout "admin_platform"
    before_action :require_super_admin!
    before_action :enter_platform_mode

    RENEWAL_WINDOW_DAYS = 30
    LIST_LIMIT = 50

    def index
      now = Time.current.in_time_zone(Platform::DashboardSummary::ZONE)
      issued = Invoice.open_issued
      overdue = issued.where("due_on < ?", now.to_date)

      @paid_this_month_cents = Invoice.where(status: "paid", paid_at: now.beginning_of_month..now).sum(:amount_cents)
      @outstanding_cents = issued.sum(:amount_cents)
      @overdue_count = overdue.count
      @overdue_cents = overdue.sum(:amount_cents)

      @overdue_invoices = overdue.includes(:store).order(:due_on, :id).limit(LIST_LIMIT)
      @issued_invoices = issued.includes(:store).order(:due_on, :id).limit(LIST_LIMIT)
      @renewals = Store.where(billing_status: %w[active trial past_due])
        .where.not(billing_period_ends_on: nil)
        .where(billing_period_ends_on: now.to_date..(now.to_date + RENEWAL_WINDOW_DAYS))
        .order(:billing_period_ends_on, :id)
        .limit(LIST_LIMIT)
      @plans = Store.order(:name).limit(200).select(:id, :name, :slug, :plan, :billing_status, :billing_interval, :billing_amount_cents, :billing_period_ends_on)
    end

    private

    def enter_platform_mode
      session[:admin_mode] = "platform"
    end
  end
end
