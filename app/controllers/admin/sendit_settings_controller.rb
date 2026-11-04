# frozen_string_literal: true

module Admin
  # Runtime delivery options belong with the connection; API keys still go through
  # DeliveryAccountsController's verified connection dialog.
  class SenditSettingsController < BaseController
    before_action :require_workspace!

    def update
      if current_store.update(settings_params)
        redirect_to settings_location, notice: t("sendit_settings.saved"), status: :see_other
      else
        redirect_to settings_location, alert: current_store.errors.full_messages.to_sentence, status: :see_other
      end
    end

    # Older workspaces can have credentials directly on Store, without a managed
    # account. Never use this endpoint to bypass deletion of a managed connection.
    def destroy
      current_store.with_lock do
        if current_store.sendit_delivery_account.present?
          return redirect_to settings_location, alert: t("sendit_settings.managed_delete_required"), status: :see_other
        end

        current_store.update!(sendit_public_key: nil, sendit_secret_key: nil, sendit_webhook_secret: nil)
      end
      clear_sendit_cache
      redirect_to settings_location, notice: t("sendit_settings.deleted"), status: :see_other
    end

    def refresh_cities
      unless current_store.sendit_configured?
        return redirect_to settings_location, alert: t("sendit_settings.connect_to_refresh"), status: :see_other
      end

      SenditCitiesRefreshJob.perform_later(current_store.id)
      redirect_to settings_location, notice: t("sendit_settings.refresh_queued"), status: :see_other
    end

    private

    def settings_params
      attrs = params.require(:store).permit(
        :sendit_pickup_district_id, :sendit_allow_open, :sendit_allow_try,
        :sendit_webhook_secret, :shipping_dh, :free_shipping_threshold_dh
      )
      attrs.delete(:sendit_webhook_secret) if attrs[:sendit_webhook_secret].blank?
      attrs
    end

    def clear_sendit_cache
      Rails.cache.delete("sendit:token:store:#{current_store.id}")
      Rails.cache.delete(Sendit::Districts.cache_key(current_store))
      Rails.cache.delete("#{Sendit::Districts.cache_key(current_store)}:pickup")
    end

    def settings_location
      seller_integrations_path(anchor: "sendit-settings")
    end

    def require_workspace!
      head :not_found unless current_store
    end
  end
end
