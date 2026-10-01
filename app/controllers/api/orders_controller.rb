# frozen_string_literal: true

module Api
  class OrdersController < BaseController
    before_action :set_order
    before_action -> { authenticate_order_action!("confirm") }, only: :confirm
    before_action -> { authenticate_order_action!("cancel") }, only: :cancel

    def confirm
      apply_transition!("confirmed", success_title: "Order validated", success_message: "Order %{number} is now confirmed.")
    end

    def cancel
      reason = params[:reason].presence || "Rejected via Discord"
      apply_transition!("cancelled", success_title: "Order rejected", success_message: "Order %{number} was cancelled.", reason: reason)
    end

    private

    def set_order
      @order = Order.find(params[:id])
    end

    def apply_transition!(to_status, success_title:, success_message:, reason: nil)
      if @order.status == to_status
        return respond_with_result(
          ok: true,
          title: "Already #{to_status}",
          message: "Order #{@order.number} is already #{to_status}.",
          status: :ok,
          order: @order
        )
      end

      unless @order.can_transition_to?(to_status)
        return respond_with_result(
          ok: false,
          title: "Cannot update",
          message: "Order #{@order.number} is #{@order.status} and cannot move to #{to_status}.",
          status: :unprocessable_entity,
          order: @order
        )
      end

      @order.transition_to!(to_status, reason: reason)
      respond_with_result(
        ok: true,
        title: success_title,
        message: format(success_message, number: @order.number),
        status: :ok,
        order: @order
      )
    rescue ArgumentError, StandardError => e
      respond_with_result(
        ok: false,
        title: "Update failed",
        message: e.message,
        status: :unprocessable_entity,
        order: @order
      )
    end
  end
end
