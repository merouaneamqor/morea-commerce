# frozen_string_literal: true

require "rails_helper"
require "nokogiri"

RSpec.describe "Platform features console", type: :request do
  let(:password) { "synthetic-platform-features-password-123" }
  let!(:super_admin) do
    User.create!(
      email: "platform-features-#{SecureRandom.hex(5)}@example.test",
      password: password,
      admin: true,
      super_admin: true
    )
  end
  let!(:store) do
    Store.create!(
      slug: "pf-#{SecureRandom.hex(5)}",
      name: "Platform features workspace",
      currency: "MAD",
      storefront_enabled: true,
      storefront_theme_editor_enabled: false
    )
  end
  let!(:other_store) do
    Store.create!(
      slug: "pf-other-#{SecureRandom.hex(5)}",
      name: "Other platform features workspace",
      currency: "MAD",
      storefront_enabled: true,
      storefront_theme_editor_enabled: false
    )
  end
  let!(:merchant) do
    store.users.create!(
      email: "platform-features-merchant-#{SecureRandom.hex(5)}@example.test",
      password: password,
      admin: true
    )
  end

  before { host! Store.base_domain }

  def sign_in(user)
    post "/admin/login", params: { email: user.email, password: password }
    expect(response).to have_http_status(:redirect)
  end

  it "requires authentication and rejects merchant administrators" do
    get "/admin/platform/features"
    expect(response).to redirect_to(admin_login_path)

    host! "#{store.slug}.#{Store.base_domain}"
    sign_in(merchant)
    host! Store.base_domain
    get "/admin/platform/features"
    expect(response).to redirect_to(admin_root_path)
  end

  it "shows home gates, theme editor state, and flag history for a super admin" do
    PlatformSetting.current.update!(home_maintenance: false, home_coming_soon: false)
    sign_in(super_admin)

    get "/admin/platform/features"

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    expect(document.at_css("[data-platform-features-home]")).to be_present
    expect(document.at_css('[data-home-effective="live"]')).to be_present
    expect(document.at_css(%([data-store-id="#{store.id}"][data-theme-editor="false"]))).to be_present
    expect(document.at_css("[data-platform-features-history]")).to be_present
    expect(response.body).to include(I18n.t("platform_admin.features.title"))
    expect(response.body).to include(store.name, other_store.name)
    expect(response.body).to include('data-turbo-confirm')
  end

  it "enables and disables the theme editor for one workspace with audit and effective state" do
    sign_in(super_admin)

    patch "/admin/platform/features/update_store", params: { store_id: store.id, enabled: "1" }

    expect(response).to redirect_to(admin_platform_features_path)
    expect(flash[:notice]).to eq(
      I18n.t("platform_admin.features.updated_store", name: store.name, status: I18n.t("platform_admin.features.enabled"))
    )
    expect(store.reload).to be_storefront_theme_editor_enabled
    expect(other_store.reload).not_to be_storefront_theme_editor_enabled

    follow_redirect!
    expect(Nokogiri::HTML(response.body).at_css(%([data-store-id="#{store.id}"][data-theme-editor="true"]))).to be_present

    event = AuditEvent.where(action: "feature_flag.theme_editor", store_id: store.id).order(:id).last
    expect(event).to have_attributes(actor_user_id: super_admin.id, acting_as_platform: true)
    expect(event.metadata).to include("flag" => "storefront_theme_editor_enabled", "enabled" => true)

    patch "/admin/platform/features/update_store", params: { store_id: store.id, enabled: "0" }

    expect(response).to redirect_to(admin_platform_features_path)
    expect(flash[:notice]).to eq(
      I18n.t("platform_admin.features.updated_store", name: store.name, status: I18n.t("platform_admin.features.disabled"))
    )
    expect(store.reload).not_to be_storefront_theme_editor_enabled
    expect(other_store.reload).not_to be_storefront_theme_editor_enabled

    follow_redirect!
    expect(Nokogiri::HTML(response.body).at_css(%([data-store-id="#{store.id}"][data-theme-editor="false"]))).to be_present
    expect(AuditEvent.where(action: "feature_flag.theme_editor", store_id: store.id).count).to eq(2)
  end

  it "toggles home maintenance and coming soon with audit and effective visitor state" do
    PlatformSetting.current.update!(home_maintenance: false, home_coming_soon: false)
    sign_in(super_admin)

    patch "/admin/platform/features/update_home", params: { flag: "home_coming_soon", enabled: "1" }
    expect(response).to redirect_to(admin_platform_features_path)
    follow_redirect!
    expect(PlatformSetting.current.reload).to be_home_coming_soon
    expect(PlatformSetting.current.home_page).to eq("coming_soon")
    expect(Nokogiri::HTML(response.body).at_css('[data-home-effective="coming_soon"]')).to be_present

    patch "/admin/platform/features/update_home", params: { flag: "home_maintenance", enabled: "1" }
    follow_redirect!
    expect(PlatformSetting.current.reload.home_page).to eq("maintenance")
    expect(Nokogiri::HTML(response.body).at_css('[data-home-effective="maintenance"]')).to be_present

    home_events = AuditEvent.where(action: "feature_flag.home").order(:id)
    expect(home_events.count).to be >= 2
    expect(home_events.last.metadata).to include("flag" => "home_maintenance", "enabled" => true)

    patch "/admin/platform/features/update_home", params: { flag: "storefront_theme_editor_enabled", enabled: "1" }
    expect(response).to redirect_to(admin_platform_features_path)
    expect(flash[:alert]).to eq(I18n.t("platform_admin.features.unknown_flag"))
  end

  it "keeps the ActiveAdmin feature flags route and platform CTA" do
    route = Rails.application.routes.recognize_path("/superadmin/feature_flags")
    expect(route).to include(controller: "superadmin/feature_flags", action: "index")
    expect(File.read(Rails.root.join("app/admin/feature_flags.rb"))).to include("admin_platform_features_path")
  end
end
