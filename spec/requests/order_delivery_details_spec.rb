require "rails_helper"
require "nokogiri"

RSpec.describe "Order delivery details", type: :request do
  let(:password) { "synthetic-password-123" }
  let(:store) { Store.create!(slug: "od-#{SecureRandom.hex(5)}", name: "Walkfit", currency: "MAD") }
  let(:owner) { store.users.create!(name: "Owner", email: "owner-#{SecureRandom.hex(4)}@example.test", password: password, admin: true) }
  let(:product) { store.products.create!(name: "Tracksuit", price_cents: 20_000, status: "active") }

  before do
    host! "#{store.slug}.#{Store.base_domain}"
    post "/admin/login", params: { email: owner.email, password: password }
    store.delivery_accounts.create!(provider: "sendit", name: "Sendit", connected_at: Time.current)
  end

  it "creates an order from the window and shows the second phone, company, day, advance and what is left to collect" do
    post "/admin/orders", params: { order: { name: "Karim", phone: "0612345678", second_phone: "0698765432", address: "Rue 1", city: "Casablanca",
      delivery_provider: "sendit", scheduled_for: "2026-12-24T10:30", shipping_dh: "30", advance_dh: "50", notes: "Call first",
      lines: { "0" => { product_id: product.id, quantity: 2 } } } }

    order = store.orders.order(:id).last
    expect(order).to have_attributes(total_cents: 43_000, advance_cents: 5_000, delivery_provider: "sendit")
    follow_redirect!
    page = Nokogiri::HTML(response.body)
    expect(page.at_css("[data-second-phone]").text).to include("698765432")
    details = page.at_css("[data-delivery-details]")
    expect(details.at_css("[data-provider]").text.strip).to eq("Sendit")
    expect(details.at_css("[data-advance]").text).to include("50")
    expect(details.text.delete("⁦⁩").gsub(/[[:space:]]/, " ")).to include("24/12/2026").and include("380")      # 430 - 50 left to collect
  end

  it "keeps the window open with the error when the company is not connected" do
    post "/admin/orders", params: { order: { name: "Karim", phone: "0612345678", address: "Rue 1", city: "Casablanca", delivery_provider: "ozon",
      lines: { "0" => { product_id: product.id, quantity: 1 } } } }, headers: { "Turbo-Frame" => "order-modal" }

    expect(store.orders.count).to eq(0)
    expect(response).to have_http_status(:unprocessable_entity)
  end

  describe "cities and delivery prices of the chosen company" do
    let(:districts) do
      [ { id: 1, ville: "Casablanca", name: "Casablanca - Ain sebaa", price: "19" }, { id: 2, ville: "Casablanca", name: "Casablanca - Maarif", price: "19" },
        { id: 3, ville: "Rabat", name: "Rabat", price: "35" } ]
    end

    before do
      allow(Sendit::Client).to receive(:configured?).and_return(true)
      allow(Sendit::Districts).to receive(:all).and_return(districts)
      store.delivery_accounts.create!(provider: "ameex", name: "Ameex", connected_at: Time.current)
    end

    def form = Nokogiri::HTML(response.body).at_css("form[data-controller~='order-composer']")

    it "hands the window one catalog per connected company, with prices in centimes; a company without an API list has none" do
      get "/admin/orders/new", headers: { "Turbo-Frame" => "order-modal" }

      expect(form["data-controller"].split).to include("delivery-company")
      catalogs = JSON.parse(form["data-delivery-company-catalogs-value"])
      expect(catalogs.keys).to contain_exactly("ameex", "sendit")
      expect(catalogs["sendit"]["cities"]).to eq(%w[Casablanca Rabat])
      expect(catalogs["sendit"]["rates"]).to eq("Casablanca" => 1_900, "Rabat" => 3_500)           # 19 MAD and 35 MAD
      expect(catalogs["sendit"]["districts"]["Casablanca"]).to eq([ "Ain sebaa", "Maarif" ])
      expect(catalogs["ameex"]).to eq("cities" => [], "districts" => {}, "rates" => {})
    end

    it "lists no city until a company is chosen (the city is typed), and the city field is still a picker" do
      get "/admin/orders/new", headers: { "Turbo-Frame" => "order-modal" }

      expect(form["data-checkout-city-cities-value"]).to be_nil
      expect(form.at_css("[data-checkout-city-target=combobox] input[name='order[city]']")).to be_present
    end

    it "keeps the cities of the company already chosen when the window is shown again after an error" do
      post "/admin/orders", params: { order: { name: "", phone: "0612345678", delivery_provider: "sendit", city: "Rabat" } }, headers: { "Turbo-Frame" => "order-modal" }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(form["data-checkout-city-cities-value"])).to eq(%w[Casablanca Rabat])
      expect(JSON.parse(form["data-checkout-city-rates-value"])).to eq("Casablanca" => 1_900, "Rabat" => 3_500)
    end
  end
end
