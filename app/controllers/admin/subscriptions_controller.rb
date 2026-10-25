# frozen_string_literal: true

module Admin
  class SubscriptionsController < BaseController
    def show
      unless current_store
        return redirect_to admin_platform_path
      end

      @invoices = current_store.invoices.where(status: %w[issued paid void]).order(created_at: :desc).limit(20)
      @support_email = ENV["SUBSCRIPTION_SUPPORT_EMAIL"].to_s.strip
      @support_email = nil unless @support_email.match?(URI::MailTo::EMAIL_REGEXP)
    end
  end
end
