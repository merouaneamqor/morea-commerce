module Whatsapp
  # Sends the automatic message of a new order to its customer through the store's WhatsApp account, and logs it. The order shows as "sent" in the call
  # center queue. One message per order (unique index), never to a blocked number, never for an order the staff typed by hand.
  class OrderMessenger
    DEFAULT_COUNTRY = "MA".freeze

    def initialize(order, transport: nil)
      @order, @transport = order, transport
    end

    def deliver_new_order!
      account = @order.store.whatsapp_accounts.auto.order(:id).first
      return unless account
      return if WhatsappMessage.exists?(order_id: @order.id, kind: "new_order")
      return if BlockedPhone.blocked?(@order.store, @order.customer_phone, @order.second_phone)

      phone = self.class.international(@order.customer_phone)
      message = WhatsappMessage.create!(store: @order.store, whatsapp_account: account, order: @order, kind: "new_order", to_phone: phone.presence || @order.customer_phone.to_s,
                                        body: Keywords.render(account.message_template, @order))
      return fail!(message, "Invalid phone number") if phone.blank?

      send!(account, message)
    rescue ActiveRecord::RecordNotUnique
      nil
    end

    # A test message to any number, to check the connection.
    def self.deliver_test!(account:, to:, transport: nil)
      phone = international(to)
      body = "Test seallo : la connexion WhatsApp de #{account.store.name} fonctionne."
      message = WhatsappMessage.create!(store: account.store, whatsapp_account: account, kind: "test", to_phone: phone.presence || to.to_s, body: body)
      return message.tap { |row| row.update!(status: "failed", error: "Invalid phone number") } if phone.blank?

      new(nil, transport: transport).send!(account, message)
      message
    end

    # "06 12 34 56 78" -> "212612345678"; blank when it is not a valid number.
    def self.international(number)
      parsed = Phonelib.parse(number.to_s, DEFAULT_COUNTRY)
      parsed.valid? ? parsed.e164.delete("+") : nil
    end

    def send!(account, message)
      id = CloudApi.new(account: account, transport: @transport).send_text(to: message.to_phone, body: message.body)
      message.update!(status: "sent", wa_message_id: id, sent_at: Time.current)
      @order&.record_event!("whatsapp", body: "WhatsApp message sent automatically")
    rescue CloudApi::Error => e
      fail!(message, e.message)
    end

    private

    def fail!(message, reason)
      message.update!(status: "failed", error: reason.to_s.first(500))
    end
  end
end
