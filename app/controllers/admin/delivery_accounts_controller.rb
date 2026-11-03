# frozen_string_literal: true

module Admin
  # Delivery company accounts added from the Integrations API page (seallo's two-step "provider, details" dialog).
  # Sendit is a real integration: its keys are checked against Sendit's login before anything is saved.
  class DeliveryAccountsController < BaseController
    before_action :require_workspace!
    before_action :set_account, only: %i[update destroy]

    def create
      account = current_store.delivery_accounts.new(provider: submitted[:provider].to_s)
      return connect_sendit(account) if account.sendit?

      account.assign_attributes(account_params)
      account.credentials = credentials_from(submitted, {})
      account.connected_at = Time.current if account.credentials? && account.provider != "other"
      save(account, helpers.sl("Société ajoutée."))
    end

    def update
      return connect_sendit(@account) if @account.sendit?

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
        redirect_to seller_integrations_path, notice: message, status: :see_other
      else
        redirect_to seller_integrations_path, alert: account.errors.full_messages.to_sentence, status: :see_other
      end
    end

    # Sendit: check the keys with Sendit's login, store them encrypted (the secret key is never rendered back),
    # give the account its webhook token, and fetch the city list. Answers JSON for the dialog.
    def connect_sendit(account)
      keys = credentials_from(submitted, account.persisted? ? account.credentials : {})
      return render_sendit_error(t("seller_integrations.sendit.errors.missing_keys")) unless keys["api_key"].present? && keys["api_secret"].present?

      begin
        Sendit::Client.verify!(current_store, public_key: keys["api_key"], secret_key: keys["api_secret"])
      rescue Sendit::Client::Error => error
        return render_sendit_error(sendit_error_message(error), code: error.kind, detail: error.detail)
      end

      account.name = submitted[:name].presence || account.name.presence || "Sendit"
      account.credentials = keys
      account.is_active = true
      account.connected_at = Time.current
      account.generate_webhook_token
      return render_sendit_error(account.errors.full_messages.to_sentence) unless account.save

      Rails.cache.delete("sendit:token:store:#{current_store.id}")
      SenditCitiesRefreshJob.perform_later(current_store.id)
      flash[:notice] = helpers.sl(account.previously_new_record? ? "Société ajoutée." : "Société modifiée.")
      render json: { ok: true, webhook_url: account.webhook_url }
    end

    def render_sendit_error(message, code: nil, detail: nil)
      render json: { ok: false, error: message, code: code, detail: detail }.compact, status: :unprocessable_entity
    end

    # A different message for each way the login check can fail, so the merchant knows what to do.
    def sendit_error_message(error)
      key = { invalid_keys: :invalid_keys, blocked: :blocked, network: :network, rejected: :rejected }.fetch(error.kind, :unexpected)
      t("seller_integrations.sendit.errors.#{key}", status: error.status || "—", message: error.message.to_s.squish.first(160))
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
