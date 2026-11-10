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
      expect(store.home_sections.ordered.pluck(:kind)).to eq(%w[hero featured_collection rich_text])

      hero = store.home_sections.ordered.first
      expect(hero.position).to eq(0)
      expect(hero.settings).to include("link" => "collections")
      expect(hero.translations.order(:locale).pluck(:locale)).to contain_exactly("ar", "en", "fr")
      expect(hero.translations.find_by!(locale: "en").heading).to eq("Simply essential")
      expect(hero.translations.find_by!(locale: "fr").heading).to eq("L'essentiel, simplement")
      expect(hero.translations.find_by!(locale: "ar").heading).to eq("البساطة في الأساس")

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
