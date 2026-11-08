# frozen_string_literal: true

module Admin
  # Runtime options for the workspace's Ameex account. Credentials stay on Integrations.
  class AmeexSettingsController < BaseController
    before_action :require_workspace!
    before_action :set_account

    def show
    end

    def update
      return redirect_to(admin_ameex_settings_path, alert: t("carrier_settings.connect_first", carrier: "Ameex"), status: :see_other) unless @account

      if @account.update(account_params)
        redirect_to admin_ameex_settings_path, notice: t("carrier_settings.saved", carrier: "Ameex"), status: :see_other
      else
        flash.now[:alert] = @account.errors.full_messages.to_sentence
        render :show, status: :unprocessable_entity
      end
    end

    def refresh_cities
      unless current_store.ameex_configured?
        return redirect_to admin_ameex_settings_path, alert: t("carrier_settings.connect_to_refresh", carrier: "Ameex"), status: :see_other
      end

      AmeexCitiesRefreshJob.perform_later(current_store.id)
      redirect_to admin_ameex_settings_path, notice: t("carrier_settings.refresh_queued", carrier: "Ameex"), status: :see_other
    end

    private

    def set_account
      @account = current_store.ameex_delivery_account
      @provider_info = Carriers.provider("ameex")
    end

    def account_params
      params.require(:delivery_account).permit(:allow_open, :pickup_city, :delivery_fee, :return_fee, :is_active)
    end

    def require_workspace!
      head :not_found unless current_store
    end
  end
end
