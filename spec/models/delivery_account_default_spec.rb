# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Default shipping courier", type: :model do
  let(:store) { Store.create!(name: "Default #{SecureRandom.hex(4)}", slug: "def-#{SecureRandom.hex(4)}", currency: "MAD") }

  def connect(provider, name: provider.titleize, default: false)
    account = store.delivery_accounts.new(provider: provider, name: name, is_active: true, ships_by_default: default)
    account.credentials = { "api_key" => "#{provider}-id", "api_secret" => "#{provider}-secret" }
    account.save!
    account
  end

  it "uses the explicitly marked default when several connectors exist" do
    connect("sendit")
    ozon = connect("ozon", default: true)
    store.reload
    expect(store.default_shipping_provider).to eq("ozon")
    expect(store.ships_with?(:ozon)).to be(true)
    expect(store.ships_with?(:sendit)).to be(false)
    expect(ozon.reload.ships_by_default?).to be(true)
  end

  it "falls back to the only shippable account when none is marked" do
    connect("ozon")
    expect(store.reload.default_shipping_provider).to eq("ozon")
  end

  it "does not guess when several shippable accounts exist without a default" do
    connect("sendit")
    connect("ozon")
    expect(store.reload.default_shipping_provider).to be_nil
  end

  it "clears the previous default when another account is marked" do
    sendit = connect("sendit", default: true)
    ozon = connect("ozon")
    ozon.update!(ships_by_default: true)
    expect(sendit.reload.ships_by_default?).to be(false)
    expect(store.reload.default_shipping_provider).to eq("ozon")
  end
end
