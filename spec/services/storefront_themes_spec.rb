require "rails_helper"

RSpec.describe "Storefront theme lifecycle" do
  let(:store) do
    Store.create!(slug: "theme-service-#{SecureRandom.hex(5)}", name: "Theme service workspace",
      currency: "MAD", storefront_enabled: true)
  end

  def create_live_section(position: 0, heading: "Existing home page")
    section = store.home_sections.create!(kind: "rich_text", position: position, visible: true,
      settings: { "link" => "page:about" })
    section.translations.create!(locale: "en", heading: heading)
    section
  end

  describe StorefrontThemes::Install do
    it "installs a catalog theme as a draft without changing the live home page" do
      live_section = create_live_section

      theme = described_class.call(store: store, catalog_key: "atelier")

      expect(theme).to be_persisted
      expect(theme).to be_draft
      expect(theme.catalog_key).to eq("atelier")
      expect(theme.snapshot.fetch("sections")).not_to be_empty
      expect(theme.snapshot.fetch("sections").map { |section| section.fetch("kind") }).to eq(
        %w[hero ticker featured_collection image_with_text collection_list rich_text]
      )
      expect(theme.snapshot.dig("sections", 0, "translations", "en", "heading")).to eq("Pieces cut for movement")
      expect(theme.snapshot.dig("sections", 0, "translations", "en", "body")).to include("Clean lines")
      expect(store.home_sections.reload).to contain_exactly(live_section)
      expect(live_section.reload.translations.find_by!(locale: "en").heading).to eq("Existing home page")
    end

    it "rejects a catalog key that is not available" do
      expect {
        described_class.call(store: store, catalog_key: "not-a-theme")
      }.to raise_error(StorefrontThemes::Catalog::UnknownTheme)

      expect(store.storefront_themes).to be_empty
    end
  end

  describe StorefrontThemes::Publish do
    it "explicitly replaces live sections, copies translations, and demotes the prior published theme" do
      old_section = create_live_section
      prior = store.storefront_themes.create!(
        name: "Prior", catalog_key: "prior", status: "published", published_at: 2.days.ago,
        snapshot: { "sections" => [] }
      )
      replacement = StorefrontThemes::Install.call(store: store, catalog_key: "minimal")

      result = described_class.call(store: store, theme: replacement)

      expect(result).to eq(replacement)
      expect(HomeSection.exists?(old_section.id)).to be(false)
      expect(store.home_sections.ordered.pluck(:kind)).to eq(%w[hero ticker featured_collection rich_text])

      hero = store.home_sections.ordered.first
      expect(hero.position).to eq(0)
      expect(hero.settings).to include("link" => "collections")
      expect(hero.translations.order(:locale).pluck(:locale)).to contain_exactly("ar", "en", "fr")
      expect(hero.translations.find_by!(locale: "en").heading).to eq("The essentials, held")
      expect(hero.translations.find_by!(locale: "fr").heading).to eq("L'essentiel, tenu")
      expect(hero.translations.find_by!(locale: "ar").heading).to eq("الأساسيات، بوضوح")
      expect(hero.translations.find_by!(locale: "en").body).to eq("Few pieces, each useful and clear.")

      expect(replacement.reload).to be_published
      expect(replacement.published_at).to be_present
      expect(prior.reload).to be_draft
      expect(prior.published_at).to be_nil
    end

    it "rejects a theme belonging to another workspace without changing either workspace" do
      foreign = Store.create!(slug: "foreign-theme-#{SecureRandom.hex(5)}", name: "Foreign theme workspace",
        currency: "MAD", storefront_enabled: true)
      own_section = create_live_section
      foreign_theme = StorefrontThemes::Install.call(store: foreign, catalog_key: "atelier")

      expect {
        described_class.call(store: store, theme: foreign_theme)
      }.to raise_error(StorefrontThemes::Publish::StoreMismatch)

      expect(store.home_sections.reload).to contain_exactly(own_section)
      expect(foreign_theme.reload).to be_draft
    end

    it "rejects an empty snapshot so live home sections are not wiped" do
      own_section = create_live_section
      theme = StorefrontThemes::Install.call(store: store, catalog_key: "minimal")
      theme.update!(snapshot: { "sections" => [] })

      expect {
        described_class.call(store: store, theme: theme)
      }.to raise_error(StorefrontThemes::Publish::EmptyHome)

      expect(theme.reload).to be_draft
      expect(store.home_sections.reload).to contain_exactly(own_section)
    end
  end

  describe StorefrontThemes::CreateFromLive do
    it "snapshots live home sections into a draft without changing the live page" do
      live = store.home_sections.create!(kind: "image_with_text", position: 0, visible: true,
        settings: { "image_url" => "https://cdn.example.test/live.jpg", "link" => "collections", "image_position" => "right" })
      live.translations.create!(locale: "en", heading: "Live heading", body: "Live body", button_label: "Shop")
      live.translations.create!(locale: "fr", heading: "Titre live", body: "Texte live", button_label: "Acheter")
      live.translations.create!(locale: "ar", heading: "عنوان مباشر", body: "نص مباشر", button_label: "تسوق")

      theme = described_class.call(store: store)

      expect(theme).to be_draft
      expect(theme.catalog_key).to eq("from_live")
      expect(theme.name).to eq("Current home page")
      expect(store.home_sections.reload).to contain_exactly(live)

      section = theme.snapshot.fetch("sections").sole
      expect(section).to include(
        "kind" => "image_with_text",
        "visible" => true,
        "settings" => hash_including(
          "image_url" => "https://cdn.example.test/live.jpg",
          "link" => "collections",
          "image_position" => "right"
        )
      )
      expect(section.dig("translations", "en", "heading")).to eq("Live heading")
      expect(section.dig("translations", "fr", "body")).to eq("Texte live")
      expect(section.dig("translations", "ar", "button_label")).to eq("تسوق")
    end

    it "falls back to online store defaults when no live sections exist" do
      expect(store.home_sections).to be_empty

      theme = described_class.call(store: store)

      expect(theme.snapshot.fetch("sections")).not_to be_empty
      expect(theme.snapshot.fetch("sections").map { |section| section.fetch("kind") }).to include("hero")
      expect(store.home_sections.reload).to be_empty
    end
  end

  describe StorefrontThemes::Duplicate do
    it "copies a published theme into a new editable draft with a unique name" do
      source = StorefrontThemes::Install.call(store: store, catalog_key: "minimal")
      StorefrontThemes::Publish.call(store: store, theme: source)
      original_snapshot = source.reload.snapshot.deep_dup

      copy = described_class.call(store: store, theme: source)

      expect(copy).to be_persisted
      expect(copy).to be_draft
      expect(copy.name).to eq("Minimal (copy)")
      expect(copy.catalog_key).to eq("minimal")
      expect(copy.snapshot).to eq(original_snapshot)
      expect(source.reload).to be_published
      expect(source.snapshot).to eq(original_snapshot)
    end

    it "increments copy names when duplicates already exist" do
      source = StorefrontThemes::Install.call(store: store, catalog_key: "atelier")
      first = described_class.call(store: store, theme: source)
      second = described_class.call(store: store, theme: source)

      expect(first.name).to eq("Atelier (copy)")
      expect(second.name).to eq("Atelier (copy 2)")
    end

    it "rejects a theme belonging to another workspace" do
      foreign = Store.create!(slug: "foreign-dup-#{SecureRandom.hex(5)}", name: "Foreign dup",
        currency: "MAD", storefront_enabled: true)
      foreign_theme = StorefrontThemes::Install.call(store: foreign, catalog_key: "minimal")

      expect {
        described_class.call(store: store, theme: foreign_theme)
      }.to raise_error(StorefrontThemes::Duplicate::StoreMismatch)

      expect(store.storefront_themes).to be_empty
    end
  end

  describe StorefrontThemes::PreviewSections do
    it "builds visible unsaved home sections from a snapshot for storefront partials" do
      collection = store.collections.create!(name: "Preview collection", slug: "preview-collection", published: true, position: 0)
      snapshot = {
        "sections" => [
          {
            "kind" => "hero",
            "visible" => true,
            "settings" => { "link" => "collections" },
            "translations" => {
              "en" => { "heading" => "Preview hero", "button_label" => "Shop" },
              "fr" => { "heading" => "Héros aperçu", "button_label" => "Acheter" }
            }
          },
          {
            "kind" => "featured_collection",
            "visible" => false,
            "settings" => { "collection_id" => collection.id.to_s, "limit" => "4" },
            "translations" => { "en" => { "heading" => "Hidden" } }
          },
          {
            "kind" => "rich_text",
            "visible" => true,
            "settings" => {},
            "translations" => { "en" => { "body" => "Story body" } }
          }
        ]
      }

      sections = described_class.call(store: store, snapshot: snapshot)

      expect(sections.map(&:kind)).to eq(%w[hero rich_text])
      expect(sections).to all(be_new_record)
      expect(sections.first.store).to eq(store)
      I18n.with_locale(:en) do
        expect(sections.first.heading).to eq("Preview hero")
        expect(sections.last.body).to eq("Story body")
      end
      I18n.with_locale(:fr) do
        expect(sections.first.heading).to eq("Héros aperçu")
      end
      expect(store.home_sections.count).to eq(0)
    end
  end
end
