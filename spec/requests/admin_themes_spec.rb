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

  it "shows a publish preflight comparing live home and draft sections" do
    live_section(heading: "Keep live")
    theme = StorefrontThemes::Install.call(store: store, catalog_key: "minimal")
    sign_in

    get "/admin/themes/#{theme.id}"

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    expect(document.at_css("[data-theme-publish-preflight]")).to be_present
    expect(document.at_css("[data-theme-publish-live]").text).to include("1 section")
    expect(document.at_css("[data-theme-publish-live]").text).to include("Rich text")
    expect(document.at_css("[data-theme-publish-draft]").text).to include("3 sections")
    expect(document.at_css("[data-theme-publish-draft]").text).to include("Image banner")
    expect(document.at_css("[data-theme-publish-draft]").text).to include("Featured collection")
    expect(document.at_css("form[action='#{publish_admin_theme_path(theme)}']")).to be_present
  end

  it "publishes after confirmation" do
    existing = live_section
    theme = StorefrontThemes::Install.call(store: store, catalog_key: "minimal")
    sign_in

    post "/admin/themes/#{theme.id}/publish", params: { confirm: "1" }

    expect(response).to redirect_to(admin_theme_path(theme))
    expect(theme.reload).to be_published
    expect(HomeSection.exists?(existing.id)).to be(false)
    expect(store.home_sections.ordered.pluck(:kind)).to eq(%w[hero ticker featured_collection rich_text])
  end

  it "creates a draft theme from the live home page" do
    section = store.home_sections.create!(kind: "image_with_text", position: 0, visible: true,
      settings: { "link" => "page:about", "image_position" => "left" })
    section.translations.create!(locale: "en", heading: "Live home copy", body: "Keep this body", button_label: "Open")
    section.translations.create!(locale: "fr", heading: "Accueil live", body: "Conserver ce texte")
    sign_in

    expect {
      post "/admin/themes/create_from_live"
    }.to change(store.storefront_themes, :count).by(1)

    theme = store.storefront_themes.order(:created_at).last
    expect(response).to redirect_to(edit_admin_theme_path(theme))
    expect(theme).to be_draft
    expect(theme.catalog_key).to eq("from_live")
    expect(theme.snapshot.dig("sections", 0, "kind")).to eq("image_with_text")
    expect(theme.snapshot.dig("sections", 0, "settings", "link")).to eq("page:about")
    expect(theme.snapshot.dig("sections", 0, "translations", "en", "heading")).to eq("Live home copy")
    expect(theme.snapshot.dig("sections", 0, "translations", "en", "body")).to eq("Keep this body")
    expect(theme.snapshot.dig("sections", 0, "translations", "fr", "heading")).to eq("Accueil live")
    expect(store.home_sections.reload).to contain_exactly(section)
  end

  it "duplicates a published theme into an editable draft" do
    theme = StorefrontThemes::Install.call(store: store, catalog_key: "minimal")
    StorefrontThemes::Publish.call(store: store, theme: theme)
    expect(theme.reload).to be_published
    sign_in

    expect {
      post "/admin/themes/#{theme.id}/duplicate"
    }.to change(store.storefront_themes, :count).by(1)

    copy = store.storefront_themes.order(:created_at).last
    expect(response).to redirect_to(edit_admin_theme_path(copy))
    expect(copy).to be_draft
    expect(copy.name).to eq("Minimal (copy)")
    expect(copy.snapshot).to eq(theme.reload.snapshot)
    expect(theme).to be_published
  end

  it "blocks publishing an empty draft and keeps the live home page" do
    existing = live_section
    theme = StorefrontThemes::Install.call(store: store, catalog_key: "minimal")
    theme.update!(snapshot: { "sections" => [] })
    sign_in

    get "/admin/themes/#{theme.id}"
    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    expect(document.at_css("[data-theme-empty-draft]")).to be_present
    expect(document.at_css("[data-theme-publish-blocked]")).to be_present
    expect(document.at_css("form[action='#{publish_admin_theme_path(theme)}']")).to be_nil

    post "/admin/themes/#{theme.id}/publish", params: { confirm: "1" }

    expect(response).to redirect_to(admin_theme_path(theme))
    expect(flash[:alert]).to eq(I18n.t("storefront_themes.publish.empty"))
    expect(theme.reload).to be_draft
    expect(store.home_sections.reload).to contain_exactly(existing)
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
