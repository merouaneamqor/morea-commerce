# frozen_string_literal: true

require "rails_helper"
require "nokogiri"

RSpec.describe "Admin language selection", type: :request do
  let(:password) { "synthetic-language-password-123" }
  let(:store) { Store.create!(slug: "language-#{SecureRandom.hex(5)}", name: "Synthetic language workspace", currency: "MAD") }

  def document
    Nokogiri::HTML(response.body)
  end

  def language_link(locale)
    document.at_css("[data-admin-language-switcher] a[hreflang='#{locale}']")
  end

  def sign_in(user, host)
    host! host
    post "/admin/login", params: { email: user.email, password: password }
    expect(response).to have_http_status(:redirect)
  end

  def verify_language_navigation(path, params:, next_path:)
    get path, params: params.merge(locale: "fr")
    expect(response).to have_http_status(:ok)
    switcher = document.at_css("[data-admin-language-switcher]")
    expect(switcher["aria-label"]).to include("Language")
    expect(switcher["class"]).not_to match(/hidden/)
    expect(switcher.css("a").map(&:text)).to eq(%w[FR EN AR])
    expect(language_link("fr")["aria-current"]).to eq("true")

    %w[ar en fr].each do |locale|
      link = language_link(locale)
      expect(link["aria-label"]).to eq(Morea::Locales.label_for(locale))
      uri = URI.parse(link["href"])
      expect(uri.path).to eq(path)
      expect(Rack::Utils.parse_nested_query(uri.query)).to eq(params.stringify_keys.merge("locale" => locale))
      get link["href"]
      expect(response).to have_http_status(:ok)
      expect(document.at_css("html")["lang"]).to eq(locale)
      expect(document.at_css("html")["dir"]).to eq(locale == "ar" ? "rtl" : "ltr")
      expect(cookies[ApplicationController::LOCALE_COOKIE]).to eq(locale)

      get next_path
      expect(response).to have_http_status(:ok)
      expect(document.at_css("html")["lang"]).to eq(locale)
      # Return to the filtered page using the saved preference.
      get path, params: params
    end
  end

  it "lets a platform-only super admin change language and keep workspace filters" do
    user = User.create!(email: "language-super-#{SecureRandom.hex(5)}@example.test", password: password, admin: true, super_admin: true)
    sign_in(user, Store.base_domain)
    verify_language_navigation("/admin/platform", params: { "q" => "Synthetic & language", "subscription_status" => "active" }, next_path: "/admin/platform/users")
  end

  it "switches an invalid update back to the editable form instead of a write URL" do
    user = User.create!(email: "language-edit-#{SecureRandom.hex(5)}@example.test", password: password, admin: true, super_admin: true)
    sign_in(user, Store.base_domain)
    patch "/admin/platform/users/#{user.id}", params: { user: { email: "", role: "super_admin", store_id: "" } }
    expect(response).to have_http_status(:unprocessable_content)
    href = language_link("ar")["href"]
    expect(URI.parse(href).path).to eq("/admin/platform/users/#{user.id}/edit")
    get href
    expect(response).to have_http_status(:ok)
    expect(document.at_css("html")["lang"]).to eq("ar")
    expect(document.at_css("#platform-user-form")).to be_present
    expect(user.reload.email).to be_present
  end

  it "lets a merchant change language and retain order search parameters" do
    user = store.users.create!(email: "language-merchant-#{SecureRandom.hex(5)}@example.test", password: password, admin: true)
    sign_in(user, "#{store.slug}.#{Store.base_domain}")
    verify_language_navigation("/admin/orders", params: { "q" => "Synthetic & language", "status" => "new", "period" => "30" }, next_path: "/admin")
  end
end
