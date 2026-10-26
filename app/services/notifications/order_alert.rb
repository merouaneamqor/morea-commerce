module Notifications
  # Web Push alert for an order that just landed, sent to every active staff member
  # of the order's store. The payload carries the order number and total only:
  # push services relay it, so customer details never leave the app.
  class OrderAlert
    def initialize(order, vapid: Rails.configuration.x.web_push)
      @order = order
      @sender = WebPushSender.new(vapid: vapid)
    end

    def deliver
      @sender.deliver(subscriptions, payload)
    end

    private

    def subscriptions
      PushSubscription.joins(:user).merge(User.active).where(store_id: @order.store_id)
    end

    def payload
      {
        kind: "new_order",
        title: "New order ##{@order.number}",
        body: "#{@order.total_display} · #{@order.order_items.size} items",
        tag: "order-#{@order.id}",
        url: "/admin/confirmations"
      }
    end
  end
end
