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

    it "offers blue, dark, light and current with blue preselected" do
      get "/signup", params: { locale: "en" }
      expect(response).to have_http_status(:ok)
      inputs = document.css("input[name='registration[admin_theme]']")
      expect(inputs.map { |input| input["value"] }).to eq(%w[blue dark light current])
      expect(inputs.select { |input| input["checked"] }.map { |input| input["value"] }).to eq(%w[blue])
    end

    it "stores the chosen theme and applies it to the workspace created on confirmation" do
      post "/signup", params: { registration: { business_name: "Theme #{suffix}", email: "theme-#{suffix}@example.test", admin_theme: "dark" }, locale: "en" }
      registration = Registration.find_by!(email: "theme-#{suffix}@example.test")
      expect(registration.admin_theme).to eq("dark")

      user = Registrations::Confirm.call(token: registration.verification_token, password: password, password_confirmation: password)
      expect(user).to be_a(User)
      expect(user.store.admin_theme).to eq("dark")
    end

    it "rejects an unknown theme without creating a registration" do
      expect do
        post "/signup", params: { registration: { business_name: "Theme #{suffix}", email: "bad-#{suffix}@example.test", admin_theme: "neon" }, locale: "en" }
      end.not_to change(Registration, :count)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "workspace admin" do
    let(:store) { Store.create!(slug: "theme-#{suffix}", name: "Synthetic workspace", currency: "MAD", storefront_enabled: false) }
    let(:staff) { store.users.create!(email: "staff-#{suffix}@example.test", password: password, admin: true) }

    before do
      host! "#{store.slug}.#{Store.base_domain}"
      post "/admin/login", params: { email: staff.email, password: password }
    end

    it "keeps existing workspaces on the current look" do
      expect(store.admin_theme).to eq("current")
      get "/admin"
      expect(document.at_css("body.admin-body")["data-admin-theme"]).to eq("current")
    end

    it "lets staff change the theme in settings and rejects unknown values" do
      patch "/admin/store", params: { store: { admin_theme: "light" } }
      expect(store.reload.admin_theme).to eq("light")
      get "/admin"
      expect(document.at_css("body.admin-body")["data-admin-theme"]).to eq("light")

      patch "/admin/store", params: { store: { admin_theme: "neon" } }
      expect(store.reload.admin_theme).to eq("light")
    end
  end
end
