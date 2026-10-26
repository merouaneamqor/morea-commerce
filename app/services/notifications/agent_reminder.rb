module Notifications
  # A manual reminder from the desk's admins to every active confirmation agent of
  # the store. Supervisors and store admins are not sent it.
  class AgentReminder
    def initialize(store:, message:, vapid: Rails.configuration.x.web_push)
      @store = store
      @message = message
      @sender = WebPushSender.new(vapid: vapid)
    end

    def deliver
      @sender.deliver(subscriptions, payload)
    end

    private

    def subscriptions
      PushSubscription.joins(:user).merge(User.active).where(store: @store, users: { confirmation_role: "agent" })
    end

    def payload
      { kind: "reminder", title: "Confirmation reminder", body: @message, tag: "desk-reminder", url: "/admin/confirmations" }
    end
  end
end
