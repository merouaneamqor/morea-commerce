require "rails_helper"

RSpec.describe "Admin theme editor", type: :request do
  let(:password) { "synthetic-password-123" }
  let(:store) do
    Store.create!(
      slug: "theme-editor-#{SecureRandom.hex(5)}",
      name: "Theme editor workspace",
      currency: "MAD",
      storefront_enabled: true
    )
  end
  let(:staff) do
    store.users.create!(
      email: "theme-editor-#{SecureRandom.hex(5)}@example.test",
      password: password,
      admin: true
    )
  end
  let(:theme) { StorefrontThemes::Install.call(store: store, catalog_key: "minimal") }

  def sign_in(user: staff, workspace: store)
    host! "#{workspace.slug}.#{Store.base_domain}"
    post "/admin/login", params: { email: user.email, password: password }
    expect(response).to have_http_status(:redirect)
  end

  def editable_snapshot
    theme.snapshot.deep_dup
  end

  it "requires an authenticated administrator" do
    host! "#{store.slug}.#{Store.base_domain}"

    get "/admin/themes/#{theme.id}/edit"

    expect(response).to redirect_to(admin_login_path)
  end

  it "renders the draft editor with section, preview, and save hooks" do
    sign_in

    get "/admin/themes/#{theme.id}/edit"

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    expect(document.at_css("[data-theme-editor]")).to be_present
    expect(document.at_css("[data-theme-editor-sections]")).to be_present
    expect(document.at_css("[data-theme-editor-preview]")).to be_present
    expect(document.at_css("[data-theme-editor-save]")).to be_present
  end

  it "updates section order and translated text in one snapshot save" do
    sign_in
    snapshot = editable_snapshot
    moved = snapshot.fetch("sections").pop
    moved.fetch("translations").fetch("en")["body"] = "A carefully edited theme story."
    snapshot.fetch("sections").unshift(moved)

    patch "/admin/themes/#{theme.id}", params: { snapshot: snapshot }, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include("saved" => true)
    saved = theme.reload.snapshot
    expect(saved.dig("sections", 0, "kind")).to eq("rich_text")
    expect(saved.dig("sections", 0, "translations", "en", "body")).to eq("A carefully edited theme story.")
  end

  it "does not allow a published theme to be edited or updated" do
    theme.update!(status: "published")
    original = theme.snapshot.deep_dup
    sign_in

    get "/admin/themes/#{theme.id}/edit"
    expect(response).to have_http_status(:ok)
    expect(Nokogiri::HTML(response.body).at_css("[data-theme-editor-read-only]")).to be_present

    changed = original.deep_dup
    changed.dig("sections", 0, "translations", "en")["heading"] = "Must not be saved"
    patch "/admin/themes/#{theme.id}", params: { snapshot: changed }, as: :json

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body["saved"]).to be(false)
    expect(theme.reload.snapshot).to eq(original)
  end

  {
    "an unsupported section kind" => lambda { |snapshot|
      snapshot.fetch("sections").first["kind"] = "custom_script"
    },
    "an unsupported setting key" => lambda { |snapshot|
      snapshot.fetch("sections").first.fetch("settings")["javascript"] = "alert(1)"
    },
    "oversized translated content" => lambda { |snapshot|
      snapshot.dig("sections", 0, "translations", "en")["heading"] = "x" * 100_001
    }
  }.each do |description, corrupt|
    it "rejects #{description} without mutating the draft" do
      original = theme.snapshot.deep_dup
      sign_in
      invalid = original.deep_dup
      corrupt.call(invalid)

      patch "/admin/themes/#{theme.id}", params: { snapshot: invalid }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["saved"]).to be(false)
      expect(theme.reload.snapshot).to eq(original)
    end
  end

  it "returns not found for another workspace's theme on read and update" do
    foreign_store = Store.create!(
      slug: "foreign-theme-editor-#{SecureRandom.hex(5)}",
      name: "Foreign theme editor workspace",
      currency: "MAD",
      storefront_enabled: true
    )
    foreign_theme = StorefrontThemes::Install.call(store: foreign_store, catalog_key: "atelier")
    original = foreign_theme.snapshot.deep_dup
    sign_in

    get "/admin/themes/#{foreign_theme.id}/edit"
    expect(response).to have_http_status(:not_found)

    patch "/admin/themes/#{foreign_theme.id}", params: { snapshot: original }, as: :json
    expect(response).to have_http_status(:not_found)
    expect(foreign_theme.reload.snapshot).to eq(original)
  end
end
