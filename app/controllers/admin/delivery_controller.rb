# frozen_string_literal: true

module Admin
  class DeliveryController < BaseController
    def show
      return redirect_to(admin_platform_path) if super_admin? && !current_store
      return head(:not_found) unless current_store

      @delivery = DeliverySummary.new(store: current_store, start_date: params[:start_date],
        end_date: params[:end_date], status: params[:status], query: params[:q])
    end
  end
end
