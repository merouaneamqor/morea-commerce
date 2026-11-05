require "rails_helper"

RSpec.describe Confirmations::Desk, "import contact review" do
  let(:store) { Store.create!(slug: "contact-desk-#{SecureRandom.hex(5)}", name: "Synthetic contact desk", currency: "MAD") }
  let(:agent) do
    store.users.create!(email: "contact-agent-#{SecureRandom.hex(5)}@example.test", password: "Synthetic-password-123!",
      admin: false, confirmation_role: "agent")
  end
  let(:order) do
    store.orders.create!(customer_name: "Synthetic buyer", customer_phone: nil, customer_city: "Casablanca",
      customer_address: "Synthetic address", currency: "MAD", import_contact_issues: [ "phone" ])
  end
  let(:desk) { described_class.new(store: store, user: agent) }

  before { ConfirmationShift.create!(store: store, user: agent, started_at: 1.hour.ago) }

  it "refuses claiming or calling without persisting a confirmation or attempts" do
    [ :claim, :open_call ].each do |action|
      expect { desk.public_send(action, order.id) }.to raise_error(described_class::Error, I18n.t("import_contact.blocked"))
    end
    expect(OrderConfirmation.where(order: order)).to be_empty
    expect(ConfirmationAttempt.where(store: store)).to be_empty
    expect(order.reload.status).to eq("new")
  end

  it "refuses crafted call outcomes even if an older claim exists" do
    confirmation = OrderConfirmation.create!(store: store, order: order, assigned_user: agent,
      claimed_at: 5.minutes.ago, call_started_at: 1.minute.ago)
    [ "confirmed", "no_answer", "callback" ].each do |outcome|
      expect do
        desk.record(order.id, outcome: outcome, callback_at: 1.hour.from_now)
      end.to raise_error(described_class::Error, I18n.t("import_contact.blocked"))
    end
    expect(confirmation.confirmation_attempts).to be_empty
    expect(confirmation.reload.assigned_user).to eq(agent)
    expect(order.reload.status).to eq("new")
  end

  it "does not fabricate an abandoned-call attempt for an incomplete contact" do
    confirmation = OrderConfirmation.create!(store: store, order: order, assigned_user: agent,
      claimed_at: 5.minutes.ago, call_started_at: 1.minute.ago)
    expect { desk.abandon_call(order.id) }.to raise_error(described_class::Error, I18n.t("import_contact.blocked"))
    expect(confirmation.confirmation_attempts).to be_empty
    expect { desk.release(order.id) }.not_to raise_error
    expect(confirmation.reload.assigned_user).to be_nil
  end
end
