require "rails_helper"

RSpec.describe "Admin theme editor", type: :request do
  let(:password) { "synthetic-password-123" }
  let(:store) do
    Store.create!(
      slug: "theme-editor-#{SecureRandom.hex(5)}",
      name: "Theme editor workspace",
      currency: "MAD",
      storefront_enabled: true,
      storefront_theme_editor_enabled: true
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

  it "renders the draft editor with section, preview, add, and save hooks" do
    sign_in

    get "/admin/themes/#{theme.id}/edit"

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    editor = document.at_css("[data-theme-editor]")
    expect(editor).to be_present
    expect(document.at_css("[data-theme-editor-sections]")).to be_present
    expect(document.at_css("[data-theme-editor-preview]")).to be_present
    expect(document.at_css("[data-theme-editor-save]")).to be_present
    expect(document.at_css("[data-theme-editor-add]")).to be_present
    expect(document.at_css("#theme-section-picker-title")).to be_present
    expect(editor["data-theme-editor-max-sections-value"]).to eq(StorefrontThemes::UpdateSnapshot::MAX_SECTIONS.to_s)
    expect(editor["data-theme-editor-preview-url-value"]).to eq(preview_frame_admin_theme_path(theme))

    kinds = JSON.parse(editor["data-theme-editor-section-kinds-value"])
    expect(kinds.map { |entry| entry.fetch("kind") }).to eq(SectionBlock::KINDS.keys)
    expect(kinds.map { |entry| entry.fetch("label") }).to eq(SectionBlock::KINDS.values)
    expect(kinds.map { |entry| entry.fetch("description") }).to eq(SectionBlock::DESCRIPTIONS.values_at(*SectionBlock::KINDS.keys))
  end

  it "renders a storefront partial preview frame for a draft snapshot and locale" do
    sign_in
    snapshot = editable_snapshot
    snapshot.dig("sections", 0, "translations", "ar")["heading"] = "معاينة البطل"

    post "/admin/themes/#{theme.id}/preview_frame",
      params: { locale: "ar", snapshot: snapshot },
      as: :json

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    expect(document.at_css("[data-theme-preview-sections][dir='rtl'][lang='ar']")).to be_present
    expect(document.at_css("[data-preview-section='hero']")).to be_present
    expect(response.body).to include("معاينة البطل")
    expect(response.body).to include("campaign-hero")
  end

  it "marks preview sections with stable snapshot indexes for click-to-select" do
    sign_in
    snapshot = editable_snapshot
    snapshot.fetch("sections").first["visible"] = false

    post "/admin/themes/#{theme.id}/preview_frame",
      params: { locale: "en", snapshot: snapshot, selected_index: 1 },
      as: :json

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    blocks = document.css("[data-section-index]")
    expect(blocks.map { |node| node["data-section-index"] }).to eq(%w[1 2])
    expect(blocks.first["role"]).to eq("button")
    expect(blocks.first["tabindex"]).to eq("0")
    expect(blocks.first["aria-pressed"]).to eq("true")
    expect(blocks.first["data-preview-section"]).to eq("featured_collection")
    expect(blocks.last["aria-pressed"]).to eq("false")
  end

  it "renders the standalone preview page with real section markup" do
    sign_in

    get "/admin/themes/#{theme.id}/preview", params: { locale: "en" }

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    expect(document.at_css("[data-theme-preview='#{theme.id}']")).to be_present
    expect(document.at_css("[data-preview-section='hero']")).to be_present
    expect(response.body).to include("campaign-hero")
    expect(response.body).to include("Simply essential")
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

  it "saves a draft after adding and removing section kinds" do
    sign_in
    snapshot = editable_snapshot
    snapshot.fetch("sections") << {
      "kind" => "image_with_text",
      "visible" => true,
      "settings" => { "image_position" => "left" },
      "translations" => {
        "en" => { "heading" => "Added in the theme editor", "body" => "New section copy." },
        "fr" => { "heading" => "Ajouté dans l'éditeur", "body" => "Nouveau texte." },
        "ar" => { "heading" => "أضيف في المحرر", "body" => "نص جديد." }
      }
    }
    snapshot.fetch("sections").reject! { |section| section.fetch("kind") == "featured_collection" }

    patch "/admin/themes/#{theme.id}", params: { snapshot: snapshot }, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include("saved" => true)
    kinds = theme.reload.snapshot.fetch("sections").map { |section| section.fetch("kind") }
    expect(kinds).to include("image_with_text")
    expect(kinds).not_to include("featured_collection")
    expect(kinds.length).to eq(3)
    expect(theme.snapshot.dig("sections", -1, "translations", "en", "heading")).to eq("Added in the theme editor")
  end

  it "allows saving an emptied draft without publishing it" do
    sign_in
    snapshot = editable_snapshot
    snapshot["sections"] = []

    patch "/admin/themes/#{theme.id}", params: { snapshot: snapshot }, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include("saved" => true)
    expect(theme.reload.snapshot.fetch("sections")).to eq([])
  end

  it "exposes remove-confirm and empty-editor copy on the draft editor" do
    sign_in

    get "/admin/themes/#{theme.id}/edit"

    expect(response).to have_http_status(:ok)
    editor = Nokogiri::HTML(response.body).at_css("[data-theme-editor]")
    expect(editor["data-theme-editor-remove-confirm-value"]).to eq(I18n.t("storefront_themes.remove_confirm"))
    expect(editor["data-theme-editor-empty-editor-value"]).to eq(I18n.t("storefront_themes.empty_editor"))
  end

  it "rejects a save that exceeds the section limit without mutating the draft" do
    original = theme.snapshot.deep_dup
    sign_in
    oversized = original.deep_dup
    blank = {
      "kind" => "rich_text",
      "visible" => true,
      "settings" => {},
      "translations" => { "en" => {}, "fr" => {}, "ar" => {} }
    }
    needed = StorefrontThemes::UpdateSnapshot::MAX_SECTIONS - oversized.fetch("sections").length + 1
    needed.times { oversized.fetch("sections") << blank.deep_dup }

    patch "/admin/themes/#{theme.id}", params: { snapshot: oversized }, as: :json

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body["saved"]).to be(false)
    expect(response.parsed_body["error"]).to match(/more than #{StorefrontThemes::UpdateSnapshot::MAX_SECTIONS}/)
    expect(theme.reload.snapshot).to eq(original)
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

  def uploaded_png
    tempfile = Tempfile.new([ "pixel", ".png" ])
    tempfile.binmode
    tempfile.write(Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="))
    tempfile.rewind
    Rack::Test::UploadedFile.new(tempfile.path, "image/png")
  end

  it "uploads a section image and returns its address" do
    sign_in

    post "/admin/themes/#{theme.id}/image", params: { image: uploaded_png }

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["url"]).to be_present
    expect(theme.reload.images).to be_attached
  end

  it "rejects a file that is not an image" do
    sign_in
    tempfile = Tempfile.new([ "notes", ".txt" ])
    tempfile.write("not an image")
    tempfile.rewind

    post "/admin/themes/#{theme.id}/image", params: { image: Rack::Test::UploadedFile.new(tempfile.path, "text/plain") }

    expect(response).to have_http_status(:unprocessable_content)
    expect(theme.reload.images).not_to be_attached
  end

  it "does not accept an upload for a published theme" do
    theme.update!(status: "published")
    sign_in

    post "/admin/themes/#{theme.id}/image", params: { image: uploaded_png }

    expect(response).to have_http_status(:unprocessable_content)
    expect(theme.reload.images).not_to be_attached
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
