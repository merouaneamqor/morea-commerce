# frozen_string_literal: true

module Admin
  # Delivery company accounts added from the Integrations API page (seallo's two-step "provider, details" dialog).
  class DeliveryAccountsController < BaseController
    before_action :require_workspace!
    before_action :set_account, only: %i[update destroy]

    def create
      account = current_store.delivery_accounts.new(account_params.merge(provider: submitted[:provider].to_s))
      account.credentials = credentials_from(submitted, {})
      account.connected_at = Time.current if account.credentials? && account.provider != "other"
      save(account, helpers.sl("Société ajoutée."))
    end

    def update
      @account.assign_attributes(account_params)
      # Keys left empty keep the saved ones.
      @account.credentials = credentials_from(submitted, @account.credentials)
      @account.connected_at ||= Time.current if @account.credentials?
      save(@account, helpers.sl("Société modifiée."))
    end

    def destroy
      @account.destroy!
      redirect_to seller_integrations_path, notice: helpers.sl("Société supprimée."), status: :see_other
    end

    private

    def save(account, message)
      if account.save
        sync_sendit(account)
        redirect_to seller_integrations_path, notice: message, status: :see_other
      else
        redirect_to seller_integrations_path, alert: account.errors.full_messages.to_sentence, status: :see_other
      end
    end

    # Morea's existing Sendit integration reads its keys from the workspace, so a Sendit account feeds them.
    def sync_sendit(account)
      keys = account.credentials
      return unless account.provider == "sendit" && account.is_active? && keys["api_key"].present? && keys["api_secret"].present?

      current_store.update!(sendit_public_key: keys["api_key"], sendit_secret_key: keys["api_secret"])
    end

    def submitted
      params.require(:delivery_account)
    end

    def account_params
      submitted.permit(:name, :contact_name, :contact_phone, :account_type, :pickup_city, :allow_open, :delivery_fee, :return_fee, :is_active)
    end

    def credentials_from(input, old)
      { "api_key" => input[:api_key].presence || old["api_key"], "api_secret" => input[:api_secret].presence || old["api_secret"] }.compact
    end

    def set_account
      @account = current_store.delivery_accounts.find(params[:id])
    end

    def require_workspace!
      head :not_found unless current_store
    end
  end
end
