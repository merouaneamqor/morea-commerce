# frozen_string_literal: true

module Admin
  # Comptabilité: the financial figures of the workspace. Every number comes from AccountingStats, and the export
  # is built from the same lines, so what is printed here and what is exported always agree.
  # Reserved to the store's owner and managers (store admins): confirmation agents never reach it.
  class AccountingController < BaseController
    include DateRangeSelection

    TABS = %w[overview income receivables debts inventory].freeze

    before_action { head :not_found unless current_store }
    before_action { head :not_found unless current_user.admin? || current_user.super_admin? }

    def show
      @stats = stats
      @tab = TABS.include?(params[:tab]) ? params[:tab] : "overview"
    end

    def export
      export = AccountingExport.new(stats)
      send_data export.to_csv, filename: export.filename, type: "text/csv; charset=utf-8", disposition: "attachment"
    end

    private

    # The date range of the picker (?from=&to=), the last one chosen on this page, or this month. An older link
    # with ?month=2026-10 still works.
    def stats
      AccountingStats.new(store: current_store, range: selected_date_range(scope: "accounting", default: "this_month", **legacy_month), basis: params[:basis])
    end

    def legacy_month
      return {} unless params[:from].blank? && params[:month].to_s.match?(/\A\d{4}-(0[1-9]|1[0-2])\z/)

      first = DateRange.parse_date("#{params[:month]}-01")
      { from: first.iso8601, to: first.end_of_month.iso8601 }
    end
  end
end
