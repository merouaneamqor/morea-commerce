module Notifications
  # Web Push for carrier statuses the desk already treats as urgent (unreachable,
  # postponed, refused, returned). Same recipient set as new-order alerts; body is
  # the carrier label only, never customer contact details.
  class DeliveryAlert
    def initialize(order, status_text:, vapid: Rails.configuration.x.web_push)
      @order = order
      @status_text = status_text.to_s
      @vapid = vapid
    end

    def deliver
      return 0 if @status_text.blank?

      Push.new(@order.store, vapid: @vapid).deliver(
        kind: "delivery_update",
        title: "Delivery ##{@order.number}",
        body: @status_text.truncate(120),
        tag: "delivery-#{@order.id}",
        url: "/admin/orders/#{@order.id}"
      )
    end
  end
end
