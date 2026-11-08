# frozen_string_literal: true

module Webhooks
  # Receives Ozon Express status webhooks. Merchants paste the URL (with token) in Ozon's UI —
  # there is no API to register the webhook yet.
  #
  # Payload: { "orderid", "orderStatus", "situation", "note" }
  class OzonController < ActionController::API
    def create
      store = Store.find_by(slug: params[:store_slug].to_s)
      return head(:not_found) unless store
      return head(:unauthorized) unless authorized?(store)

      payload = parse_payload
      code = (payload["orderid"] || payload["orderId"] || payload["tracking-number"]).to_s
      order = store.orders.find_by(ozon_code: code)
      unless order
        Rails.logger.info("[Ozon webhook] Ignoring unknown parcel #{code} for store #{store.slug}")
        return render(json: { ok: true, ignored: true })
      end

      Ozon::Sync.new(order).apply_status!(
        payload["orderStatus"] || payload["order_status"] || payload["STATUS"],
        message: payload["note"].presence || payload["situation"]
      )
      render json: { ok: true, order: order.number, status: order.status }
    rescue JSON::ParserError
      head :bad_request
    end

    private

    def authorized?(store)
      tokens = store.delivery_accounts.where(provider: "ozon", is_active: true).where.not(webhook_token: nil).pluck(:webhook_token)
      return false if tokens.empty?

      given = params[:token].to_s
      return false if given.blank?

      tokens.any? { |token| ActiveSupport::SecurityUtils.secure_compare(token, given) }
    end

    def parse_payload
      if request.form_data? || request.media_type.to_s.include?("urlencoded")
        params.permit(:orderid, :orderId, :orderStatus, :order_status, :STATUS, :situation, :note, "tracking-number").to_h
      else
        JSON.parse(request.raw_post.presence || "{}")
      end
    end
  end
end
