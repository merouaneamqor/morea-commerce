require "rails_helper"

RSpec.describe "Admin storefront themes", type: :request do
  let(:password) { "synthetic-password-123" }
  let(:store) do
    Store.create!(slug: "theme-admin-#{SecureRandom.hex(5)}", name: "Theme admin workspace",
      currency: "MAD", storefront_enabled: true, storefront_theme_editor_enabled: true)
  end
  let(:staff) do
    store.users.create!(email: "theme-admin-#{SecureRandom.hex(5)}@example.test", password: password, admin: true)
  end

  def sign_in
    host! "#{store.slug}.#{Store.base_domain}"
    post "/admin/login", params: { email: staff.email, password: password }
    expect(response).to have_http_status(:redirect)
  end

  def live_section(heading: "Keep this")
    section = store.home_sections.create!(kind: "rich_text", position: 0, visible: true)
    section.translations.create!(locale: "en", heading: heading)
    section
  end

  it "requires an authenticated administrator" do
    host! "#{store.slug}.#{Store.base_domain}"

    get "/admin/themes"

    expect(response).to redirect_to(admin_login_path)
  end

  it "installs a valid catalog theme as a draft without replacing live sections" do
    existing = live_section
    sign_in

    post "/admin/themes/install", params: { catalog_key: "atelier" }

    theme = store.storefront_themes.order(:created_at).last
    expect(response).to redirect_to(admin_theme_path(theme))
    expect(theme).to be_draft
    expect(store.home_sections.reload).to contain_exactly(existing)
  end

  it "rejects an unavailable catalog theme" do
    sign_in

    expect {
      post "/admin/themes/install", params: { catalog_key: "unavailable" }
    }.not_to change(store.storefront_themes, :count)

    expect(response).to redirect_to(admin_themes_path)
    expect(flash[:alert]).to eq("That theme is not available.")
  end

  it "requires explicit confirmation before replacing the home page" do
    existing = live_section
    theme = StorefrontThemes::Install.call(store: store, catalog_key: "minimal")
    sign_in

    post "/admin/themes/#{theme.id}/publish"

    expect(response).to redirect_to(admin_theme_path(theme))
    expect(flash[:alert]).to match(/Confirm that you want to replace/)
    expect(theme.reload).to be_draft
    expect(store.home_sections.reload).to contain_exactly(existing)
  end

  it "publishes after confirmation" do
    existing = live_section
    theme = StorefrontThemes::Install.call(store: store, catalog_key: "minimal")
    sign_in

    post "/admin/themes/#{theme.id}/publish", params: { confirm: "1" }

    expect(response).to redirect_to(admin_theme_path(theme))
    expect(theme.reload).to be_published
    expect(HomeSection.exists?(existing.id)).to be(false)
    expect(store.home_sections.ordered.pluck(:kind)).to eq(%w[hero featured_collection rich_text])
  end

  it "does not expose or publish another workspace's theme" do
    foreign = Store.create!(slug: "foreign-admin-theme-#{SecureRandom.hex(5)}", name: "Foreign workspace",
      currency: "MAD", storefront_enabled: true)
    foreign_theme = StorefrontThemes::Install.call(store: foreign, catalog_key: "atelier")
    existing = live_section
    sign_in

    get "/admin/themes/#{foreign_theme.id}"
    expect(response).to have_http_status(:not_found)

    post "/admin/themes/#{foreign_theme.id}/publish", params: { confirm: "1" }
    expect(response).to have_http_status(:not_found)
    expect(foreign_theme.reload).to be_draft
    expect(store.home_sections.reload).to contain_exactly(existing)
  end
end
