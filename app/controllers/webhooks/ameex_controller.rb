# frozen_string_literal: true

module Webhooks
  # Receives Ameex form-encoded status webhooks.
  # Auth: ?token= on the URL. Optional X-Ameex-Signature when a webhook secret is stored.
  class AmeexController < ActionController::API
    def create
      store = Store.find_by(slug: params[:store_slug].to_s)
      return head(:not_found) unless store
      return head(:unauthorized) unless authorized?(store)

      code = (params[:CODE] || params[:code]).to_s
      order = store.orders.find_by(ameex_code: code)
      unless order
        Rails.logger.info("[Ameex webhook] Ignoring unknown parcel #{code} for store #{store.slug}")
        return render(json: { ok: true, ignored: true })
      end

      Ameex::Sync.new(order).apply_status!(
        params[:STATUT] || params[:statut],
        message: params[:COMMENT].presence || params[:STATUT_NAME].presence || params[:comment]
      )
      render json: { ok: true, order: order.number, status: order.status }
    end

    private

    def authorized?(store)
      return false unless valid_token?(store)
      return true unless signature_required?(store)

      valid_signature?(store)
    end

    def valid_token?(store)
      tokens = store.delivery_accounts.where(provider: "ameex", is_active: true).where.not(webhook_token: nil).pluck(:webhook_token)
      return false if tokens.empty?

      given = params[:token].to_s
      return false if given.blank?

      tokens.any? { |token| ActiveSupport::SecurityUtils.secure_compare(token, given) }
    end

    def signature_required?(store)
      store.delivery_accounts.where(provider: "ameex", is_active: true).any? { |a| a.credentials["webhook_secret"].present? }
    end

    def valid_signature?(store)
      header = request.headers["X-Ameex-Signature"].to_s
      match = header.match(/\At=(\d+),v1=([0-9a-f]+)\z/i)
      return false unless match

      raw = request.raw_post
      secrets = store.delivery_accounts.where(provider: "ameex", is_active: true).filter_map { |a| a.credentials["webhook_secret"].presence }
      secrets.any? do |secret|
        expected = OpenSSL::HMAC.hexdigest("SHA256", secret, "#{match[1]}.#{raw}")
        ActiveSupport::SecurityUtils.secure_compare(expected, match[2])
      end
    end
  end
end
