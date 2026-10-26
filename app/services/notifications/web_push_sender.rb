module Notifications
  # Sends one Web Push payload to each subscription. A browser that revoked its
  # subscription is removed; other delivery failures are logged and skipped.
  class WebPushSender
    def initialize(vapid: Rails.configuration.x.web_push)
      @vapid = vapid
    end

    # Returns how many subscriptions accepted the payload. Nothing is sent without VAPID keys.
    def deliver(subscriptions, payload)
      return 0 unless @vapid[:public_key].present? && @vapid[:private_key].present?

      subscriptions.find_each.count { |subscription| send_to(subscription, payload) }
    end

    private

    def send_to(subscription, payload)
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
      subscription.destroy!
      false
    rescue WebPush::ResponseError => e
      Rails.logger.warn("Web push not delivered to subscription #{subscription.id}: #{e.class}")
      false
    end
  end
end
