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

  describe "changing the plan with one click" do
    let(:paid_plan) { Plans.list.keys.find { |key| !Plans.free?(key) } }

    before { store.update!(plan: "free", billing_interval: "monthly") }

    it "keeps the plans link on the host the owner is already signed in on, so the sign-in is not lost" do
      sign_in(owner, Store.base_domain)
      get admin_orders_path
      expect(page.at_css("a[data-plan-card]")["href"]).to eq("http://#{Store.base_domain}/abonnement?locale=fr")
      expect(Store.apex_host?("localhost")).to be(true)
      host! "localhost"
      post "/admin/login", params: { email: owner.email, password: password }
      get admin_orders_path
      expect(page.at_css("a[data-plan-card]")["href"]).to eq("http://localhost/abonnement?locale=fr")
    end

    it "applies the chosen plan at once, as if it were paid, without a signup or a payment step" do
      sign_in(owner, Store.base_domain)
      get "/abonnement"
      expect(response).to have_http_status(:ok)

      post "/abonnement", params: { plan: paid_plan, billing: "monthly", currency: "MAD" }
      expect(response).to redirect_to(%r{/admin(\?|\z)})
      expect(flash[:notice]).to eq(I18n.t("signup_plans.changed"))
      store.reload
      expect(store).to have_attributes(plan: paid_plan, billing_status: "active", subscription_required: true)
      expect(store.billing_period_ends_on).to be >= Date.current + 27.days
      expect(store.operational_access?).to be(true)

      post "/abonnement", params: { plan: "free", billing: "monthly", currency: "MAD" }
      expect(store.reload).to have_attributes(plan: "free", subscription_required: false)
    end

    it "brings the payment step back when PLANS_SKIP_PAYMENT is off" do
      allow(Plans).to receive(:skip_payment?).and_return(false)
      sign_in(owner, Store.base_domain)
      post "/abonnement", params: { plan: paid_plan, billing: "monthly", currency: "MAD" }
      expect(response).to redirect_to(payment_path(locale: I18n.locale))
      expect(store.reload.billing_status).to eq("trial")
    end
  end
end
