module Notifications
  # Web Push alert for an order that just landed, sent to every active staff member
  # of the order's store. The payload carries the order number and total only:
  # push services relay it, so customer details never leave the app.
  class OrderAlert
    def initialize(order, vapid: Rails.configuration.x.web_push)
      @order = order
      @vapid = vapid
    end

    def deliver
      return 0 unless @vapid[:public_key] && @vapid[:private_key]

      subscriptions.find_each.count { |subscription| send_to(subscription) }
    end

    private

    def subscriptions
      PushSubscription.joins(:user).merge(User.active).where(store_id: @order.store_id)
    end

    def send_to(subscription)
      WebPush.payload_send(
        message: payload.to_json,
        endpoint: subscription.endpoint,
        p256dh: subscription.p256dh,
        auth: subscription.auth,
        ttl: 3600,
        urgency: "high",
        vapid: { subject: @vapid[:subject], public_key: @vapid[:public_key], private_key: @vapid[:private_key] }
      )
      true
    rescue WebPush::ExpiredSubscription, WebPush::InvalidSubscription
      # The browser revoked or replaced this subscription; stop sending to it.
      subscription.destroy!
      false
    rescue WebPush::ResponseError => e
      Rails.logger.warn("Order alert not delivered to subscription #{subscription.id}: #{e.class}")
      false
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
