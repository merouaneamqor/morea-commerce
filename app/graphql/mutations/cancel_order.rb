# frozen_string_literal: true

module Mutations
  class CancelOrder < BaseMutation
    argument :number, String, required: true
    argument :confirm, Boolean, required: true
    argument :reason, String, required: false

    field :order, Types::Analytics::OrderType, null: true
    field :errors, [ String ], null: false

    def resolve(number:, confirm:, reason: nil)
      return { order: nil, errors: [ "Set confirm: true to cancel." ] } unless confirm

      order = store.orders.find_by(number: number.to_s.strip)
      return { order: nil, errors: [ "Order not found: #{number}" ] } unless order
      return { order: order, errors: [ refusal(order) ] } unless order.can_transition_to?("cancelled")

      order.transition_to!("cancelled", reason: reason.to_s.strip.presence, source: :staff)
      { order: order.reload, errors: [] }
    rescue ArgumentError, StandardError => e
      { order: order, errors: [ e.message ] }
    end

    private

    def refusal(order)
      if order.status == "cancelled"
        "Order #{order.number} is already cancelled."
      else
        "Order #{order.number} cannot be cancelled from #{order.status}. Cancel is available before pickup: #{CANCELLABLE.join(", ")}."
      end
    end

    CANCELLABLE = Order::TRANSITIONS.select { |_status, next_statuses| next_statuses.include?("cancelled") }.keys.freeze
  end
end
