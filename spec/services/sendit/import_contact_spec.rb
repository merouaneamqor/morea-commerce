require "rails_helper"

RSpec.describe Sendit::Sync, "import contact review" do
  let(:store) { Store.create!(slug: "contact-sendit-#{SecureRandom.hex(5)}", name: "Synthetic delivery workspace", currency: "MAD") }
  let(:order) do
    store.orders.create!(customer_name: "Synthetic buyer", customer_phone: nil, customer_city: "Casablanca",
      customer_address: "Synthetic address", currency: "MAD", import_contact_issues: [ "phone" ])
  end
  let(:client) { instance_double(Sendit::Client) }
  let(:sync) { described_class.new(order, client: client) }

  it "blocks parcel creation before resolving a district or contacting Sendit" do
    expect(client).not_to receive(:create_delivery)
    expect(Sendit::Districts).not_to receive(:match)
    expect { sync.push! }.not_to change { ActiveJob::Base.queue_adapter.enqueued_jobs.size }
    expect(order.reload.sendit_code).to be_nil
    expect(order.sendit_error).to eq(I18n.t("import_contact.blocked"))
    expect(order.status).to eq("new")
  end

  it "blocks parcel updates before any carrier call" do
    expect(client).not_to receive(:update_delivery)
    sync.update!
    expect(order.reload.sendit_error).to eq(I18n.t("import_contact.blocked"))
  end

  it "blocks refresh from falling through to parcel creation" do
    expect(client).not_to receive(:create_delivery)
    expect(client).not_to receive(:delivery)
    sync.refresh!
    expect(order.reload.sendit_error).to eq(I18n.t("import_contact.blocked"))
  end
end
