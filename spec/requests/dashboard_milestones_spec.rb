require "rails_helper"
require "nokogiri"

RSpec.describe "Dashboard milestones", type: :request do
  let(:password) { "synthetic-password-123" }
  let(:store) { Store.create!(slug: "dm-#{SecureRandom.hex(5)}", name: "Dm", currency: "MAD", storefront_enabled: false) }
  let(:owner) { store.users.create!(name: "Owner", email: "owner-#{SecureRandom.hex(4)}@example.test", password: password, admin: true) }
  let(:customer) { store.customers.create!(name: "Client", phone: "0612345678") }

  def document = Nokogiri::HTML(response.body)

  before do
    store.orders.create!(customer: customer, number: "MS1", status: "delivered", currency: "MAD", customer_name: "C", customer_phone: "0612345678",
      customer_city: "Fès", customer_address: "x", subtotal_cents: 22_421_000, total_cents: 22_421_000, delivered_at: 2.days.ago, created_at: 2.days.ago)
    host! "#{store.slug}.#{Store.base_domain}"
    post "/admin/login", params: { email: owner.email, password: password }
  end

  it "prints the ladder from the milestones service" do
    get "/dashboard", params: { locale: "fr" }

    expect(response).to have_http_status(:ok)
    section = document.at_css("[data-milestones]")
    expect(section.at_css("[data-milestone-revenue]")["data-milestone-revenue"]).to eq("22421000")
    expect(section.at_css("[data-milestone-current]").text.squish).to eq("Pionnier")
    expect(section.css("[data-tier]").map { |tier| [ tier["data-tier"], tier["data-unlocked"], tier["data-fill"] ] }).to eq(
      [ %w[pionnier true 100], %w[doyen false 31], %w[leader false 0], %w[maitre false 0], %w[legende false 0], %w[titan false 0] ]
    )
    expect(section.css("[data-current=true]").map { |tier| tier["data-tier"] }).to eq([ "pionnier" ])
    text = section.at_css("[data-milestone-remaining]").text.gsub(/[⁦⁩]/, "").squish
    expect(text).to include("275 790", "Doyen", "31 %")
  end

  it "renders in English and Arabic without a missing translation" do
    %w[en ar].each do |locale|
      get "/dashboard", params: { locale: locale }
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("translation missing")
    end
  end
end
