# frozen_string_literal: true

require "rails_helper"
require "nokogiri"

RSpec.describe "Admin funnel traffic page", type: :request do
  let(:password) { "synthetic-funnel-password-123" }
  let(:store) { Store.create!(slug: "fun-#{SecureRandom.hex(5)}", name: "Synthetic Funnel", currency: "MAD", storefront_enabled: true) }
  let(:staff) { store.users.create!(email: "fun-#{SecureRandom.hex(5)}@example.test", password: password, admin: true) }
  let(:other) { Store.create!(slug: "fun-oth-#{SecureRandom.hex(5)}", name: "Other workspace", currency: "MAD", storefront_enabled: true) }

  def tenant_host = "#{store.slug}.#{Store.base_domain}"

  def sign_in(user = staff)
    host! tenant_host
    post "/admin/login", params: { email: user.email, password: password }
    expect(response).to have_http_status(:redirect)
  end

  def document
    Nokogiri::HTML(response.body)
  end

  it "requires a signed-in store operator" do
    host! tenant_host
    get "/funnel"
    expect(response).to redirect_to("/admin/login")
  end

  it "shows the seller Traffic page with funnel and sources for the current store only" do
    now = Time.current
    store.storefront_visits.create!(
      token: SecureRandom.hex(8),
      utm_source: "facebook",
      funnel_stage: "checkout_started",
      landing_path: "/en/?utm_source=facebook",
      landed_at: now - 1.day,
      last_seen_at: now - 1.day
    )
    other.storefront_visits.create!(
      token: SecureRandom.hex(8),
      utm_source: "google",
      funnel_stage: "ordered",
      landing_path: "/en/",
      landed_at: now - 1.day,
      last_seen_at: now - 1.day
    )

    sign_in
    get "/funnel"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t("funnel.title"))
    expect(document.at_css("[data-funnel-stages]")).to be_present
    expect(document.at_css("[data-funnel-sources]")).to be_present
    expect(document.at_css("[data-funnel-source=meta]")).to be_present
    expect(document.at_css("[data-funnel-source=google]")).to be_nil
    active = document.css("aside nav ul a").find { |link| link["href"] == "/funnel" }
    expect(active["class"]).to include("lg-nav__active", "font-semibold")
  end
end
