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

  it "shows the runner (no pulsing dot) at the end of the fill, and a trophy only once the last tier is reached" do
    get "/dashboard", params: { locale: "fr" }
    expect(document.at_css("[data-milestones] [data-runner]")).to be_present
    expect(document.at_css("[data-milestones] [data-trophy]")).to be_nil
    expect(document.at_css("[data-runner]")["style"]).to include("left: 21.83%")   # (100 + 31) / 6 of the track
    expect(response.body).not_to include("ms-dot")

    6.times do |i|
      store.orders.create!(customer: customer, number: "MAX#{i}", status: "delivered", currency: "MAD", customer_name: "C", customer_phone: "0612345678",
        customer_city: "Fès", customer_address: "x", subtotal_cents: 1_000_000_000, total_cents: 1_000_000_000, delivered_at: 1.day.ago, created_at: 1.day.ago)
    end
    get "/dashboard", params: { locale: "fr" }
    expect(document.at_css("[data-milestones] [data-trophy]")).to be_present
    expect(document.at_css("[data-milestones] [data-runner]")).to be_nil
  end

  describe "the on/off switch" do
    it "hides the bar for the person who switched it off, offers to show it again, and remembers" do
      get "/dashboard", params: { locale: "fr" }
      expect(document.at_css("[data-milestones]")).to be_present
      expect(document.at_css("[data-hide-milestones]")).to be_present

      patch "/dashboard/paliers", params: { show: 0 }
      expect(response).to have_http_status(:see_other)
      expect(owner.reload.show_milestones).to be(false)

      get "/dashboard", params: { locale: "fr" }
      expect(document.at_css("[data-milestones]")).to be_nil
      expect(document.at_css("[data-show-milestones]")).to be_present
      expect(response.body).not_to include("data-milestone-revenue")   # the figures are not even computed for the page

      patch "/dashboard/paliers", params: { show: 1 }
      get "/dashboard", params: { locale: "fr" }
      expect(document.at_css("[data-milestones]")).to be_present
      expect(owner.reload.show_milestones).to be(true)
    end

    it "is a personal choice: a colleague keeps the bar" do
      colleague = store.users.create!(name: "Colleague", email: "col-#{SecureRandom.hex(4)}@example.test", password: password, admin: true)
      patch "/dashboard/paliers", params: { show: 0 }
      expect(colleague.reload.show_milestones).to be(true)

      post "/admin/login", params: { email: colleague.email, password: password }
      get "/dashboard", params: { locale: "fr" }
      expect(document.at_css("[data-milestones]")).to be_present
    end

    it "needs a signed-in person" do
      delete "/admin/logout"
      patch "/dashboard/paliers", params: { show: 0 }
      expect(response).to redirect_to(%r{/admin/login})
    end
  end

  it "renders in English and Arabic without a missing translation" do
    %w[en ar].each do |locale|
      get "/dashboard", params: { locale: locale }
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("translation missing")
    end
  end
end
