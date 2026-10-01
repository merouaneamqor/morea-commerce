# frozen_string_literal: true

module Api
  class BaseController < ActionController::Base
    skip_forgery_protection

    rescue_from OrderActionToken::InvalidToken do |error|
      respond_with_result(ok: false, title: "Invalid link", message: error.message, status: :unauthorized)
    end

    rescue_from ActiveRecord::RecordNotFound do
      respond_with_result(ok: false, title: "Order not found", message: "This order no longer exists.", status: :not_found)
    end

    private

    def respond_with_result(ok:, title:, message:, status:, order: nil)
      @ok = ok
      @title = title
      @message = message
      @order = order

      respond_to do |format|
        format.html { render "api/orders/result", status: status, layout: false }
        format.json do
          render json: {
            ok: ok,
            title: title,
            message: message,
            order: order && {
              id: order.id,
              number: order.number,
              status: order.status
            }
          }, status: status
        end
      end
    end

    def authenticate_order_action!(action)
      token = bearer_token.presence || params[:token].to_s
      @token_payload = OrderActionToken.verify!(
        token,
        expected_action: action,
        expected_order_id: params[:id]
      )
    end

    def bearer_token
      header = request.headers["Authorization"].to_s
      return if header.blank?

      scheme, token = header.split(" ", 2)
      token if scheme&.casecmp("Bearer")&.zero?
    end
  end
end
