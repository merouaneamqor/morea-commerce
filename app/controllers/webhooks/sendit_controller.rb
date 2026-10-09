# frozen_string_literal: true

module Webhooks
  # Receives Sendit "delivery.status.update" events (HMAC-SHA256 of the raw body
  # in X-Sendit-Signature, keyed with the API key chosen when creating the webhook)
  class SenditController < ActionController::API
    def create
      store = Store.find_by(slug: params[:store_slug].to_s)
      return head(:not_found) unless store

      body = request.raw_post
      return head(:unauthorized) unless valid_signature?(store, body, request.headers["X-Sendit-Signature"].to_s)

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
