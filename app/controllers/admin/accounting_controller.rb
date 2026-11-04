# frozen_string_literal: true

module Admin
  # Comptabilité: the financial figures of the workspace. Every number comes from AccountingStats, and the export
  # is built from the same lines, so what is printed here and what is exported always agree.
  # Reserved to the store's owner and managers (store admins): confirmation agents never reach it.
  class AccountingController < BaseController
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

    def stats
      AccountingStats.new(store: current_store, month: params[:month], basis: params[:basis])
    end
  end
end
