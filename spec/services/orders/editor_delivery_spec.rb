require "rails_helper"

RSpec.describe Orders::Editor, "delivery details, advance and excluded shipping" do
  let(:store) { Store.create!(slug: "ed-#{SecureRandom.hex(5)}", name: "Editor", currency: "MAD") }
  let(:product) { store.products.create!(name: "Tee", price_cents: 20_000, status: "active") }
  let(:editor) { described_class.new(store: store, external_effects: false) }
  let(:base) { { name: "Karim", phone: "0612345678", city: "Casablanca", address: "Rue 1", shipping_dh: 30, lines: [ { product_id: product.id, quantity: 2 } ] } }   # 400 + 30 = 430

  def connect(provider, active: true)
    store.delivery_accounts.create!(provider: provider, name: "#{provider} account", connected_at: Time.current, is_active: active)
  end

  it "saves the second phone, a connected company, the wished day (Casablanca time) and the advance in centimes" do
    connect("sendit")

    order = editor.create(base.merge(second_phone: "0698765432", delivery_provider: "sendit", scheduled_for: "2026-12-24T10:30", advance_dh: "50,5"))

    expect(order).to be_present, editor.errors.full_messages.to_sentence
    expect(order).to have_attributes(delivery_provider: "sendit", advance_cents: 5_050, total_cents: 43_000)
    expect(order.second_phone).to end_with("698765432")
    expect(order.scheduled_for.in_time_zone(DateRange::ZONE).strftime("%d/%m/%Y %H:%M")).to eq("24/12/2026 10:30")
    expect(order.to_collect_cents).to eq(37_950)                                      # 430,00 - 50,50
  end

  it "defaults to nothing: no company, no day, no advance, all to collect" do
    order = editor.create(base)

    expect(order).to have_attributes(delivery_provider: nil, scheduled_for: nil, advance_cents: 0, second_phone: nil)
    expect(order.to_collect_cents).to eq(43_000)
  end

  it "refuses a company the store is not connected to (never connected, switched off, or another store's)" do
    connect("ameex", active: false)
    other = Store.create!(slug: "ed-other-#{SecureRandom.hex(4)}", name: "Other", currency: "MAD")
    other.delivery_accounts.create!(provider: "cathedis", name: "Cathedis elsewhere", connected_at: Time.current)
    store.delivery_accounts.create!(provider: "ozon", name: "Ozon not connected")

    %w[ameex cathedis ozon sendit unknown].each do |provider|
      expect { expect(editor.create(base.merge(delivery_provider: provider))).to be_falsey }.not_to change { store.orders.count }
      expect(editor.errors.full_messages.to_sentence).to include("delivery company"), provider
    end
  end

  it "refuses a wished day that is not a date, and an advance that is not an amount or is more than the total" do
    expect(editor.create(base.merge(scheduled_for: "not a date"))).to be_falsey
    expect(editor.errors.full_messages.to_sentence).to include("not a valid date")

    expect(editor.create(base.merge(advance_dh: "abc"))).to be_falsey
    expect(editor.errors.full_messages.to_sentence).to include("must be an amount")

    expect(editor.create(base.merge(advance_dh: "-5"))).to be_falsey
    expect(editor.errors.full_messages.to_sentence).to include("cannot be negative")

    expect(editor.create(base.merge(advance_dh: "430.01"))).to be_falsey                 # one centime over the 430,00 total
    expect(editor.errors.full_messages.to_sentence).to include("cannot be more than the total")
    expect(editor.create(base.merge(advance_dh: "430"))).to be_present                # exactly the total is allowed
    expect(store.orders.count).to eq(1)
  end

  it "leaves the delivery fee out when it is excluded: the customer pays the products only" do
    order = editor.create(base.merge(shipping_excluded: "1"))

    expect(order).to have_attributes(shipping_cents: 0, total_cents: 40_000)
    expect(editor.create(base.merge(shipping_excluded: "0"))).to have_attributes(shipping_cents: 3_000, total_cents: 43_000)
  end

  it "on an update, writes only the details that are given and keeps the others" do
    connect("sendit")
    order = editor.create(base.merge(delivery_provider: "sendit", advance_dh: "100", scheduled_for: "2026-12-24T10:30"))

    editor.update(order, base.merge(advance_dh: "150"))

    expect(order.reload).to have_attributes(advance_cents: 15_000, delivery_provider: "sendit")
    expect(order.scheduled_for).to be_present
  end

  it "uses what is left to collect as the default COD amount" do
    order = editor.create(base.merge(advance_dh: "100"))
    order.update_columns(status: "delivered", delivered_at: Time.current)

    order.record_collection!(cents: order.to_collect_cents)

    expect(order.reload.collected_cents).to eq(33_000)                                # 430 - 100
  end

  it "does not let an advance be a negative number in the database" do
    order = editor.create(base)

    expect { order.update_columns(advance_cents: -1) }.to raise_error(ActiveRecord::StatementInvalid, /orders_advance_cents_nonnegative/)
  end
end
