require "rails_helper"
require "nokogiri"

# The owner can reach the plans page (to change the subscription) from the plan card of the menu and from the Abonnement page.
RSpec.describe "Changing the subscription plan", type: :request do
  let(:password) { "synthetic-password-123" }
  let(:store) { Store.create!(slug: "pl-#{SecureRandom.hex(5)}", name: "Walkfit", currency: "MAD") }
  let!(:owner) { store.users.create!(name: "Owner", email: "owner-#{SecureRandom.hex(4)}@example.test", password: password, admin: true) }
  let!(:agent) { store.users.create!(name: "Saida", email: "saida-#{SecureRandom.hex(4)}@example.test", password: password, admin: false, confirmation_role: "agent") }

  def sign_in(user, host)
    host! host
    post "/admin/login", params: { email: user.email, password: password }
  end

  def page = Nokogiri::HTML(response.body)

  it "makes the plan card of the menu a link to the plans page on the shared host, and adds a button on the Abonnement page" do
    sign_in(owner, "#{store.slug}.#{Store.base_domain}")
    get admin_orders_path
    card = page.at_css("a[data-plan-card]")
    expect(card["href"]).to eq("http://#{Store.base_domain}/abonnement?locale=fr")
    expect(card.text).to include("Walkfit")

    get admin_subscription_path
    expect(page.at_css("a[data-change-plan]")["href"]).to eq(card["href"])
  end

  it "opens the plans page for the signed-in owner, and shows agents no plan card" do
    sign_in(owner, Store.base_domain)
    get "/abonnement"
    expect(response).to have_http_status(:ok)

    delete admin_logout_path rescue nil
    sign_in(agent, "#{store.slug}.#{Store.base_domain}")
    get admin_my_stats_path
    expect(page.at_css("a[data-plan-card]")).to be_nil
  end
end
