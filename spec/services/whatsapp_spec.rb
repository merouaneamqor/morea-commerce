require "rails_helper"

# The automatic WhatsApp message of a new order: keywords, the Cloud API call (never live: a fake transport answers), the log, and when it is NOT sent.
RSpec.describe "WhatsApp automatic messages" do
  let(:store) { Store.create!(slug: "wa-#{SecureRandom.hex(5)}", name: "Walkfit", currency: "MAD") }
  let(:customer) { store.customers.create!(name: "Karim", phone: "0612345678") }
  let(:account) do
    store.whatsapp_accounts.create!(name: "Walkfit", display_phone: "+212 600-000000", phone_number_id: "1318994621304711", business_account_id: "1119867737576759",
                                    access_token: "EAAG-secret-token-1234", auto_send_new_orders: true)
  end
  let(:reply) { Struct.new(:code, :body) }
  let(:requests) { [] }
  let(:ok_transport) { ->(uri, request) { requests << [ uri, request ]; reply.new("200", { messages: [ { id: "wamid.ABC" } ] }.to_json) } }

  def make_order(phone: "0612345678", **attrs)
    store.orders.create!({ customer: customer, number: "W#{SecureRandom.hex(3)}", status: "new", currency: "MAD", customer_name: "Karim", customer_phone: phone, customer_city: "Fès",
                           customer_address: "Rue 1", subtotal_cents: 25_000, total_cents: 25_000 }.merge(attrs))
  end

  describe Whatsapp::Keywords do
    it "fills the keywords with the order's values and leaves nothing behind" do
      order = make_order
      order.order_items.create!(product_name: "Survêtement", variant_name: "L", quantity: 2, unit_price_cents: 12_500, total_cents: 25_000)
      text = described_class.render("Bonjour {{nom_client}}, {{ numero_commande }} : {{produits}} ({{total}}) à {{ville}} par {{boutique}}", order)
      expect(text).to eq("Bonjour Karim, ##{order.number} : 2 × Survêtement (L) (250 MAD) à Fès par Walkfit")
    end

    it "knows which keywords are not real" do
      expect(described_class.unknown_in("Salut {{nom_client}} {{prix_secret}}")).to eq([ "prix_secret" ])
    end
  end

  describe WhatsappAccount do
    it "keeps the token encrypted, shows only its end, and refuses unknown keywords or a bad phone number id" do
      expect(account.access_token).to eq("EAAG-secret-token-1234")
      expect(account.access_token_ciphertext).not_to include("EAAG")
      expect(account.token_hint).to eq("••••1234")
      expect(account.tap { |row| row.new_order_message = "Salut {{inconnu}}" }).not_to be_valid
      expect(store.whatsapp_accounts.new(name: "x", phone_number_id: "abc", access_token: "t")).not_to be_valid
    end
  end

  describe Whatsapp::CloudApi do
    it "posts the text to the account's number with its token, and returns the id Meta gave" do
      id = described_class.new(account: account, transport: ok_transport).send_text(to: "+212 612-345678", body: "Salam")
      uri, request = requests.first
      expect(id).to eq("wamid.ABC")
      expect(uri.to_s).to eq("https://graph.facebook.com/v21.0/1318994621304711/messages")
      expect(request["Authorization"]).to eq("Bearer EAAG-secret-token-1234")
      expect(JSON.parse(request.body)).to include("messaging_product" => "whatsapp", "to" => "212612345678", "type" => "text", "text" => { "preview_url" => false, "body" => "Salam" })
    end

    it "turns Meta's errors and unreadable answers into a clear error" do
      bad = ->(_uri, _request) { reply.new("400", { error: { message: "Recipient not in allowed list" } }.to_json) }
      expect { described_class.new(account: account, transport: bad).send_text(to: "212612345678", body: "x") }.to raise_error(Whatsapp::CloudApi::Error, "Recipient not in allowed list")
      garbled = ->(_uri, _request) { reply.new("502", "<html>") }
      expect { described_class.new(account: account, transport: garbled).send_text(to: "212612345678", body: "x") }.to raise_error(Whatsapp::CloudApi::Error, /unreadable/)
    end
  end

  describe Whatsapp::OrderMessenger do
    it "sends the store's message once, logs it, and shows the order as WhatsApp-sent in the queue" do
      account
      order = make_order
      messenger = described_class.new(order, transport: ok_transport)
      messenger.deliver_new_order!
      messenger.deliver_new_order!

      expect(requests.size).to eq(1)
      message = WhatsappMessage.find_by!(order: order)
      expect(message).to have_attributes(kind: "new_order", status: "sent", wa_message_id: "wamid.ABC", to_phone: "212612345678", whatsapp_account_id: account.id)
      expect(message.body).to include("Karim", "##{order.number}", "Walkfit")
      expect(order.order_events.where(kind: "whatsapp")).to exist
    end

    it "logs a failure with Meta's reason and does not mark the order as sent" do
      account
      order = make_order
      failing = ->(_uri, _request) { reply.new("400", { error: { message: "Template required" } }.to_json) }
      described_class.new(order, transport: failing).deliver_new_order!

      expect(WhatsappMessage.find_by!(order: order)).to have_attributes(status: "failed", error: "Template required")
      expect(order.order_events.where(kind: "whatsapp")).not_to exist
    end

    it "does not message an invalid number, a blocked number, or a store without the option switched on" do
      account
      invalid = make_order(phone: "123")
      described_class.new(invalid, transport: ok_transport).deliver_new_order!
      expect(WhatsappMessage.find_by!(order: invalid).status).to eq("failed")

      BlockedPhone.block!(store: store, phone: "0698765432", reason: "spam", user: nil)
      blocked = make_order(phone: "0698765432")
      described_class.new(blocked, transport: ok_transport).deliver_new_order!
      expect(WhatsappMessage.where(order: blocked)).not_to exist

      account.update!(auto_send_new_orders: false)
      quiet = make_order
      described_class.new(quiet, transport: ok_transport).deliver_new_order!
      expect(WhatsappMessage.where(order: quiet)).not_to exist
      expect(requests).to be_empty
    end

    it "sends a test message to any number" do
      message = described_class.deliver_test!(account: account, to: "06 12 34 56 78", transport: ok_transport)
      expect(message).to have_attributes(kind: "test", status: "sent", to_phone: "212612345678", order_id: nil)
    end
  end

  describe "when an order arrives" do
    it "queues the message for an order that comes from a store, but not for one the staff typed by hand, nor without an account" do
      expect { make_order }.not_to have_enqueued_job(WhatsappOrderMessageJob)

      account
      expect { make_order }.to have_enqueued_job(WhatsappOrderMessageJob)
      expect { make_order(skip_auto_whatsapp: true) }.not_to have_enqueued_job(WhatsappOrderMessageJob)

      staff = store.users.create!(name: "Owner", email: "o-#{SecureRandom.hex(4)}@example.test", password: "synthetic-password-123", admin: true)
      expect { Orders::Editor.new(store: store, user: staff).create(name: "Karim", phone: "0612345678", city: "Fès", address: "Rue 1", lines: []) }.not_to have_enqueued_job(WhatsappOrderMessageJob)
    end
  end
end
