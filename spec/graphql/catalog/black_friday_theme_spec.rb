# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Catalog Black Friday theme" do
  let(:store) do
    Store.create!(
      slug: "gql-bf-#{SecureRandom.hex(4)}",
      name: "GQL BF",
      currency: "MAD",
      storefront_enabled: true
    )
  end

  def execute(query, variables: {})
    MoreaSchema.execute(query, variables: variables, context: { store: store, source: "spec" })
  end

  it "sets and reads blackFridayTheme through StoreOps and GraphQL" do
    expect(Catalog::StoreOps.set_black_friday_theme!(store, enabled: true).black_friday_theme).to be(true)
    expect(Catalog::StoreOps.set_black_friday_theme!(store, enabled: true).black_friday_theme).to be(true)
    expect(Catalog::StoreOps.set_black_friday_theme!(store, enabled: false).black_friday_theme).to be(false)

    store.update!(black_friday_theme: true)
    result = execute(<<~GQL)
      mutation {
        setBlackFridayTheme(enabled: false) {
          settings { blackFridayTheme }
          errors
        }
      }
    GQL
    expect(result.dig("data", "setBlackFridayTheme", "errors")).to eq([])
    expect(result.dig("data", "setBlackFridayTheme", "settings", "blackFridayTheme")).to eq(false)
    expect(store.reload.black_friday_theme).to be(false)

    read = execute("{ storeSettings { blackFridayTheme } }")
    expect(read.dig("data", "storeSettings", "blackFridayTheme")).to eq(false)
  end
end
