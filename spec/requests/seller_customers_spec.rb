# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Seller customers page", type: :request do
  let(:suffix) { SecureRandom.hex(5) }
  let(:password) { "Synthetic-seller-#{suffix}-pw" }
  let(:store) { Store.create!(name: "Boutique #{suffix}", slug: "shop-#{suffix}", currency: "MAD", storefront_enabled: false) }
  let(:owner) { store.users.create!(email: "maker-#{suffix}@example.test", name: "Salma", password: password, admin: true) }
  let(:host) { "#{store.slug}.#{Store.base_domain}" }

  before do
    host! host
    post "/admin/login", params: { email: owner.email, password: password }
  end

  def document
    Nokogiri::HTML(response.body)
  end

  def customer(name, phone)
    store.customers.create!(name: name, phone: phone, email: "#{name.downcase}-#{suffix}@example.test", city: "Fès")
  end

  def order(customer, status, total: 10_000)
    store.orders.create!(customer: customer, number: "C#{SecureRandom.hex(4)}", status: status, currency: "MAD", customer_name: customer.name, customer_phone: customer.phone,
      customer_city: "Fès", customer_address: "Rue 1", subtotal_cents: total, total_cents: total)
  end

  def names
    document.css("table tbody tr td:first-child p:first-child").map(&:text)
  end

  it "is served at the seallo URL with the clients entry highlighted" do
    get "/clients"
    expect(response).to have_http_status(:ok)
    expect(document.at_css("h1").text).to eq("Clients")
    expect(document.at_css("aside nav ul a.font-semibold")["href"]).to eq("/clients")
    expect(response.body).to include("Aucun client pour le moment.")
  end

  it "counts and filters loyal, at risk and new customers" do
    loyal = customer("Loyal", "0611111111")
    order(loyal, "delivered", total: 25_000)
    order(loyal, "in_transit")
    risky = customer("Risky", "0622222222")
    order(risky, "returned")
    fresh = customer("Fresh", "0633333333")
    order(fresh, "new")
    customer("Silent", "0644444444")

    get "/clients"
    expect(document.css("section.grid > a").map { |tab| tab.at_css("p:last-child").text.delete("⁦⁩") }).to eq(%w[4 1 1 2])

    get "/clients", params: { segment: "loyal" }
    expect(names).to eq([ "Loyal" ])
    expect(response.body.delete("⁦⁩")).to include("250 MAD")
    expect(response.body.delete("⁦⁩")).to include("1 en cours")
    get "/clients", params: { segment: "risky" }
    expect(names).to eq([ "Risky" ])
    get "/clients", params: { segment: "new" }
    expect(names).to contain_exactly("Fresh", "Silent")
  end

  it "searches by name, phone or city" do
    customer("Amina", "0655555555")
    store.customers.create!(name: "Bilal", phone: "0666666666", email: "bilal-#{suffix}@example.test", city: "Tanger")
    get "/clients", params: { q: "amina" }
    expect(names).to eq([ "Amina" ])
    get "/clients", params: { q: "0666" }
    expect(names).to eq([ "Bilal" ])
    get "/clients", params: { q: "tanger" }
    expect(names).to eq([ "Bilal" ])
  end

  it "lists the most recently active customers first and paginates by 25" do
    old = customer("Ancien", "0600000001")
    order(old, "delivered").update_columns(created_at: 3.days.ago)
    recent = customer("Recent", "0600000002")
    order(recent, "delivered")
    get "/clients"
    expect(names.first(2)).to eq(%w[Recent Ancien])

    26.times { |i| customer("Bulk#{i}", "07#{format("%08d", i)}") }
    get "/clients"
    expect(names.length).to eq(25)
    expect(response.body).to include("1–25 / 28")
    get "/clients", params: { page: 2 }
    expect(names.length).to eq(3)
    get "/clients", params: { page: 99 }
    expect(response).to have_http_status(:ok)
  end

  it "only shows the workspace's own customers" do
    customer("Mine", "0677777777")
    other = Store.create!(name: "Autre #{suffix}", slug: "autre-#{suffix}", currency: "MAD")
    other.customers.create!(name: "Foreign", phone: "0688888888", email: "foreign-#{suffix}@example.test")
    get "/clients"
    expect(names).to eq([ "Mine" ])
    expect(response.body).not_to include("Foreign")
  end

  it "still serves the same page on the admin URL and keeps the old segment name working" do
    risky = customer("Risky", "0622222222")
    order(risky, "returned")
    get "/admin/customers", params: { segment: "at_risk" }
    expect(names).to eq([ "Risky" ])
  end

  %w[fr en ar].each do |locale|
    it "renders in #{locale} without missing translations" do
      customer("Amina", "0655555555")
      get "/clients", params: { locale: locale }
      expect(response).to have_http_status(:ok)
      expect(document.at_css("html")["dir"]).to eq(locale == "ar" ? "rtl" : "ltr")
      expect(response.body).not_to match(/translation missing/i)
    end
  end
end
