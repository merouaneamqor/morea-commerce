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

  it "shows an \"I'm here\" bubble at the end of the fill (no person, no dot), the next goal in words, and a trophy only at the last tier" do
    get "/dashboard", params: { locale: "fr" }
    expect(document.at_css("[data-milestones] [data-here]").text.squish).to eq("Je suis ici")
    expect(document.at_css("[data-milestone-goal]").text.squish).to eq("Je continue jusqu'à 500K MAD")   # the next tier, Doyen
    expect(document.at_css("[data-milestones] [data-trophy]")).to be_nil
    expect(document.at_css("[data-here]")["style"]).to include("--ms-pos: 21.83%")   # (100 + 31) / 6 of the track
    expect(response.body).not_to include("data-runner")
    expect(response.body).not_to include("ms-dot")

    6.times do |i|
      store.orders.create!(customer: customer, number: "MAX#{i}", status: "delivered", currency: "MAD", customer_name: "C", customer_phone: "0612345678",
        customer_city: "Fès", customer_address: "x", subtotal_cents: 1_000_000_000, total_cents: 1_000_000_000, delivered_at: 1.day.ago, created_at: 1.day.ago)
    end
    get "/dashboard", params: { locale: "fr" }
    expect(document.at_css("[data-milestones] [data-trophy]")).to be_present
    expect(document.at_css("[data-milestones] [data-here]")).to be_nil
  end

  it "gives every stage its own colour: solid with a tick once unlocked, a tinted lock of the same colour before" do
    get "/dashboard", params: { locale: "fr" }

    tiers = document.css("[data-tier]")
    colors = tiers.map { |tier| tier["data-color"] }
    expect(colors).to eq(%w[#3aa76d #3b82c4 #7c5cd6 #e08a2c #d6455d #1c1c1e])
    expect(colors.uniq.size).to eq(6)
    unlocked, locked = tiers.partition { |tier| tier["data-unlocked"] == "true" }
    expect(unlocked.map { |tier| tier.at_css("span")["style"] }).to eq([ "background: #3aa76d; color: #fff" ])
    expect(locked.first.at_css("span")["style"]).to eq("background: color-mix(in srgb, #3b82c4 18%, white); color: #3b82c4")   # Doyen, still locked
    fill = document.at_css(".ms-fill")["style"]
    expect(fill).to include("--ms-w: 21.83%", "#3aa76d 0.0% 16.667%", "#3b82c4 16.667% 33.333%", "#1c1c1e 83.333% 100.0%")
    expect(document.at_css("[data-milestone-current]")["style"]).to include("#3aa76d")   # Pionnier
    expect(document.at_css("[data-here] span")["style"]).to include("#3b82c4")            # the stage being filled
  end

  it "shows the four headline figures as flat rectangles" do
    get "/dashboard", params: { locale: "fr" }

    cards = document.css("[data-kpis=headline] [data-kpi]")
    expect(cards.map { |card| card["data-kpi"] }).to eq(%w[revenue orders confirmation_rate average_basket])
    expect(cards.map { |card| card["class"][/min-h-\[\d+px\]/] }.uniq).to eq([ "min-h-[72px]" ])
    expect(cards).to all(satisfy { |card| card["class"].include?("items-center") && !card["class"].include?("flex-col") }) # icon beside the text, not above it
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
