# frozen_string_literal: true

module Admin
  # Delivery company accounts added from the Integrations API page (seallo's two-step "provider, details" dialog).
  # Sendit / Ozon / Ameex: keys are checked live against the courier API before anything is saved or shown as connected.
  class DeliveryAccountsController < BaseController
    before_action :require_workspace!
    before_action :set_account, only: %i[update destroy make_default]

    def create
      account = current_store.delivery_accounts.new(provider: submitted[:provider].to_s)
      return connect_api_courier(account) if DeliveryAccount::SHIPPABLE.include?(account.provider)

      account.assign_attributes(account_params)
      account.credentials = credentials_from(submitted, {})
      # Manual carriers only: no live key check yet. API couriers never reach this path.
      account.connected_at = Time.current if account.credentials? && account.provider != "other"
      save(account, helpers.sl("Société ajoutée."))
    end

    def update
      return connect_api_courier(@account) if DeliveryAccount::SHIPPABLE.include?(@account.provider)

      @account.assign_attributes(account_params)
      # Keys left empty keep the saved ones.
      @account.credentials = credentials_from(submitted, @account.credentials)
      @account.connected_at ||= Time.current if @account.credentials?
      save(@account, helpers.sl("Société modifiée."))
    end

    def make_default
      unless DeliveryAccount::SHIPPABLE.include?(@account.provider) && @account.credentials? && @account.is_active?
        return redirect_to seller_integrations_path, alert: helpers.sl("Seules Sendit, Ozon Express et Ameex connectées peuvent être la société par défaut."), status: :see_other
      end

      @account.update!(ships_by_default: true)
      redirect_to seller_integrations_path, notice: helpers.sl("Société par défaut pour l'envoi des colis mise à jour."), status: :see_other
    end

    def destroy
      sendit = @account.sendit?
      ozon = @account.ozon?
      ameex = @account.ameex?
      current_store.with_lock do
        effective_sendit = sendit && @account.is_active? && @account.credentials?
        @account.destroy!
        # Do not silently reactivate an older Store-level connection when the
        # merchant removes their final active, encrypted Sendit account.
        if effective_sendit && !current_store.delivery_accounts.where(provider: "sendit", is_active: true).where.not(credentials_ciphertext: nil).exists?
          current_store.update!(sendit_public_key: nil, sendit_secret_key: nil, sendit_webhook_secret: nil)
        end
      end
      if sendit
        Rails.cache.delete("sendit:token:store:#{current_store.id}")
        Rails.cache.delete(Sendit::Districts.cache_key(current_store))
        Rails.cache.delete("#{Sendit::Districts.cache_key(current_store)}:pickup")
      elsif ozon
        Rails.cache.delete(Ozon::Cities.cache_key)
      elsif ameex
        Rails.cache.delete(Ameex::Cities.cache_key(current_store))
      end
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

    def connect_api_courier(account)
      case account.provider
      when "sendit" then connect_sendit(account)
      when "ozon" then connect_ozon(account)
      when "ameex" then connect_ameex(account)
      else
        render_courier_error(helpers.sl("Cette société de livraison n'a pas encore de connecteur API."))
      end
    end

    # Check keys with the courier API first. Only on success: encrypt, mark connected, return webhook URL.
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
      account.ships_by_default = true if claim_default_shipping?(account)
      return render_sendit_error(account.errors.full_messages.to_sentence) unless account.save

      Rails.cache.delete("sendit:token:store:#{current_store.id}")
      SenditCitiesRefreshJob.perform_later(current_store.id)
      flash[:notice] = helpers.sl(account.previously_new_record? ? "Société ajoutée." : "Société modifiée.")
      render json: { ok: true, webhook_url: account.webhook_url, ships_by_default: account.ships_by_default? }
    end

    def connect_ozon(account)
      keys = credentials_from(submitted, account.persisted? ? account.credentials : {})
      return render_courier_error(t("seller_integrations.ozon.errors.missing_keys")) unless keys["api_key"].present? && keys["api_secret"].present?

      begin
        Ozon::Client.verify!(current_store, customer_id: keys["api_key"], api_key: keys["api_secret"])
      rescue Ozon::Client::Error => error
        return render_courier_error(ozon_error_message(error), code: error.kind, detail: error.detail)
      end

      account.name = submitted[:name].presence || account.name.presence || "Ozon Express"
      account.credentials = keys
      account.is_active = true
      account.connected_at = Time.current
      account.generate_webhook_token
      account.ships_by_default = true if claim_default_shipping?(account)
      return render_courier_error(account.errors.full_messages.to_sentence) unless account.save

      OzonCitiesRefreshJob.perform_later(current_store.id)
      flash[:notice] = helpers.sl(account.previously_new_record? ? "Société ajoutée." : "Société modifiée.")
      render json: { ok: true, webhook_url: account.webhook_url, ships_by_default: account.ships_by_default? }
    end

    def connect_ameex(account)
      old = account.persisted? ? account.credentials : {}
      keys = credentials_from(submitted, old)
      keys["webhook_secret"] = submitted[:webhook_secret].presence || old["webhook_secret"]
      keys.compact!
      return render_courier_error(t("seller_integrations.ameex.errors.missing_keys")) unless keys["api_key"].present? && keys["api_secret"].present?

      begin
        Ameex::Client.verify!(current_store, api_id: keys["api_key"], api_key: keys["api_secret"])
      rescue Ameex::Client::Error => error
        return render_courier_error(ameex_error_message(error), code: error.kind, detail: error.detail)
      end

      account.name = submitted[:name].presence || account.name.presence || "Ameex"
      account.credentials = keys
      account.is_active = true
      account.connected_at = Time.current
      account.generate_webhook_token
      account.ships_by_default = true if claim_default_shipping?(account)
      return render_courier_error(account.errors.full_messages.to_sentence) unless account.save

      AmeexCitiesRefreshJob.perform_later(current_store.id)
      flash[:notice] = helpers.sl(account.previously_new_record? ? "Société ajoutée." : "Société modifiée.")
      render json: { ok: true, webhook_url: account.webhook_url, ships_by_default: account.ships_by_default? }
    end

    # First connected shippable courier becomes default; later ones keep the merchant's choice.
    def claim_default_shipping?(account)
      return true if submitted[:ships_by_default].to_s == "true"
      return false if submitted[:ships_by_default].to_s == "false"

      others = current_store.delivery_accounts.where(provider: DeliveryAccount::SHIPPABLE, is_active: true)
                            .where.not(credentials_ciphertext: nil)
      others = others.where.not(id: account.id) if account.persisted?
      others.none?
    end

    def render_sendit_error(message, code: nil, detail: nil)
      render_courier_error(message, code: code, detail: detail)
    end

    def render_courier_error(message, code: nil, detail: nil)
      render json: { ok: false, error: message, code: code, detail: detail }.compact, status: :unprocessable_entity
    end

    # A different message for each way the login check can fail, so the merchant knows what to do.
    def sendit_error_message(error)
      key = { invalid_keys: :invalid_keys, blocked: :blocked, network: :network, rejected: :rejected }.fetch(error.kind, :unexpected)
      t("seller_integrations.sendit.errors.#{key}", status: error.status || "—", message: error.message.to_s.squish.first(160))
    end

    def ozon_error_message(error)
      key = { invalid_keys: :invalid_keys, blocked: :blocked, network: :network, rejected: :rejected }.fetch(error.kind, :unexpected)
      t("seller_integrations.ozon.errors.#{key}", status: error.status || "—", message: error.message.to_s.squish.first(160))
    end

    def ameex_error_message(error)
      key = { invalid_keys: :invalid_keys, blocked: :blocked, network: :network, rejected: :rejected }.fetch(error.kind, :unexpected)
      t("seller_integrations.ameex.errors.#{key}", status: error.status || "—", message: error.message.to_s.squish.first(160))
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
