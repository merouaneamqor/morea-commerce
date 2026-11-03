# frozen_string_literal: true

module Webhooks
  # Receives Sendit "delivery.status.update" events and updates the parcel's order in real time.
  #
  # A workspace that connected Sendit from the Integrations page has a secret token in its webhook URL
  # (`?token=...`); every call must carry it. Workspaces that only have the older HMAC setup
  # (X-Sendit-Signature, keyed with the secret chosen when the webhook was created) keep working
  # until they connect Sendit from the Integrations page.
  class SenditController < ActionController::API
    def create
      store = Store.find_by(slug: params[:store_slug].to_s)
      return head(:not_found) unless store

      body = request.raw_post
      return head(:unauthorized) unless authorized?(store, body)

      payload = JSON.parse(body)
      order = store.orders.find_by(sendit_code: payload["code"].to_s)
      unless order
        Rails.logger.info("[Sendit webhook] Ignoring unknown parcel #{payload["code"]} for store #{store.slug}")
        return render(json: { ok: true, ignored: true })
      end

      Sendit::Sync.new(order).apply_status!(
        payload["newStatus"],
        message: payload["message"],
        deliver_by: payload["deliverBy"]
      )
      render json: { ok: true, order: order.number, status: order.status }
    rescue JSON::ParserError
      head :bad_request
    end

    private

    def authorized?(store, body)
      tokens = store.delivery_accounts.where(provider: "sendit", is_active: true).where.not(webhook_token: nil).pluck(:webhook_token)
      return valid_token?(tokens) if tokens.any?

      valid_signature?(store, body, request.headers["X-Sendit-Signature"].to_s)
    end

    def valid_token?(tokens)
      given = params[:token].to_s
      return false if given.blank?

      tokens.map { |token| ActiveSupport::SecurityUtils.secure_compare(token, given) }.any?
    end

    def valid_signature?(store, body, signature)
      return false if signature.blank?

      secrets = [
        store.sendit_webhook_secret,
        store.sendit_secret_key,
        store.sendit_public_key
      ].compact_blank.uniq
      secrets.any? do |secret|
        digest = OpenSSL::HMAC.digest("SHA256", secret, body)
        [ digest.unpack1("H*"), Base64.strict_encode64(digest) ].any? do |expected|
          ActiveSupport::SecurityUtils.secure_compare(expected, signature.strip.delete_prefix("sha256="))
        end
      end
    end
  end
end
