# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin theme", type: :request do
  let(:suffix) { SecureRandom.hex(6) }
  let(:password) { "Synthetic-theme-#{suffix}-pw" }

  def document
    Nokogiri::HTML(response.body)
  end

  describe "onboarding" do
    before { host! Store.base_domain }

    it "starts workspaces created by signup on the seallo look" do
      post "/signup", params: { signup: { name: "Theme Owner", store_name: "Theme #{suffix}", phone: "0612345678", email: "maker-#{suffix}@example.test",
                                          password: password, password_confirmation: password, currency: "USD" }, locale: "en" }
      expect(User.find_by!(email: "maker-#{suffix}@example.test").store.admin_theme).to eq("seallo")
    end

    it "applies the theme of a pending registration to the workspace created on confirmation" do
      registration = Registration.create!(business_name: "Theme #{suffix}", email: "pending-#{suffix}@example.test", locale: "en",
                                          admin_theme: "seallo_dark", verification_sent_at: Time.current)
      user = Registrations::Confirm.call(token: registration.verification_token, password: password, password_confirmation: password)
      expect(user).to be_a(User)
      expect(user.store.admin_theme).to eq("seallo_dark")
    end

    it "rejects an unknown theme on a registration" do
      registration = Registration.new(business_name: "Theme #{suffix}", email: "bad-#{suffix}@example.test", locale: "en", admin_theme: "neon")
      expect(registration).not_to be_valid
    end
  end

  describe "workspace admin" do
    let(:store) { Store.create!(slug: "theme-#{suffix}", name: "Synthetic workspace", currency: "MAD", storefront_enabled: false) }
    let(:staff) { store.users.create!(email: "staff-#{suffix}@example.test", password: password, admin: true) }

    before do
      host! "#{store.slug}.#{Store.base_domain}"
      post "/admin/login", params: { email: staff.email, password: password }
    end

    it "defaults workspaces to the seallo look" do
      expect(store.admin_theme).to eq("seallo")
      get "/admin"
      expect(document.at_css("body.admin-body")["data-admin-theme"]).to eq("seallo")
    end

    it "lets staff change the theme in settings and rejects unknown values" do
      patch "/admin/store", params: { store: { admin_theme: "seallo_dark" } }
      expect(store.reload.admin_theme).to eq("seallo_dark")
      get "/admin"
      expect(document.at_css("body.admin-body")["data-admin-theme"]).to eq("seallo_dark")
      expect(document.css("link[rel=stylesheet]").map { |link| link["href"] }.join(" ")).to include("admin_dark")
      expect(document.at_css("meta[name=theme-color]")["content"]).to eq("#15110f")

      patch "/admin/store", params: { store: { admin_theme: "neon" } }
      expect(store.reload.admin_theme).to eq("seallo_dark")
    end
  end
end
