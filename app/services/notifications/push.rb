module Notifications
  # Low-level Web Push send to every active staff subscription on a store.
  # Payloads must stay free of customer contact details: push relays are third parties.
  class Push
    def initialize(store, vapid: Rails.configuration.x.web_push)
      @store = store
      @vapid = vapid
    end

    def deliver(payload)
      return 0 unless @vapid[:public_key] && @vapid[:private_key]

      message = payload.to_json
      subscriptions.find_each.count { |subscription| send_to(subscription, message) }
    end

    private

    def subscriptions
      PushSubscription.joins(:user).merge(User.active).where(store_id: @store.id)
    end

    def send_to(subscription, message)
      WebPush.payload_send(
        message: message,
        endpoint: subscription.endpoint,
        p256dh: subscription.p256dh,
        auth: subscription.auth,
        ttl: 3600,
        urgency: "high",
        vapid: { subject: @vapid[:subject], public_key: @vapid[:public_key], private_key: @vapid[:private_key] }
      )
      true
    rescue WebPush::ExpiredSubscription, WebPush::InvalidSubscription, WebPush::Unauthorized
      # Browser revoked the subscription, or it was created with a different VAPID key.
      subscription.destroy!
      false
    rescue WebPush::ResponseError => e
      Rails.logger.warn("Push alert not delivered to subscription #{subscription.id}: #{e.class}")
      false
    end
  end
end
