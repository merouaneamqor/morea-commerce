# frozen_string_literal: true

module Admin
  # Runtime options for the workspace's Ozon Express account. Credentials stay on Integrations.
  class OzonSettingsController < BaseController
    before_action :require_workspace!
    before_action :set_account

    def show
    end

    def update
      return redirect_to(admin_ozon_settings_path, alert: t("carrier_settings.connect_first", carrier: "Ozon Express"), status: :see_other) unless @account

      if @account.update(account_params)
        redirect_to admin_ozon_settings_path, notice: t("carrier_settings.saved", carrier: "Ozon Express"), status: :see_other
      else
        flash.now[:alert] = @account.errors.full_messages.to_sentence
        render :show, status: :unprocessable_entity
      end
    end

    def refresh_cities
      unless current_store.ozon_configured?
        return redirect_to admin_ozon_settings_path, alert: t("carrier_settings.connect_to_refresh", carrier: "Ozon Express"), status: :see_other
      end

      OzonCitiesRefreshJob.perform_later(current_store.id)
      redirect_to admin_ozon_settings_path, notice: t("carrier_settings.refresh_queued", carrier: "Ozon Express"), status: :see_other
    end

    private

    def set_account
      @account = current_store.ozon_delivery_account
      @provider_info = Carriers.provider("ozon")
    end

    def account_params
      params.require(:delivery_account).permit(:allow_open, :pickup_city, :delivery_fee, :return_fee, :is_active)
    end

    def require_workspace!
      head :not_found unless current_store
    end
  end
end
