# frozen_string_literal: true

require "rails_helper"

RSpec.describe StorefrontThemes::UpdateSnapshot do
  let(:store) do
    Store.create!(slug: "snap-#{SecureRandom.hex(4)}", name: "Snapshot", currency: "MAD", storefront_enabled: true)
  end
  let(:theme) { StorefrontThemes::Install.call(store: store, catalog_key: "minimal") }

  def snapshot_with(sections)
    { "sections" => sections }
  end

  def rich_text_section(overrides = {})
    {
      "kind" => "rich_text",
      "visible" => true,
      "settings" => { "link" => "page:about" },
      "translations" => { "en" => { "body" => "Hello" } }
    }.deep_merge(overrides)
  end

  it "persists a normalized draft snapshot" do
    result = described_class.call(
      store: store,
      theme: theme,
      snapshot: snapshot_with([ rich_text_section ])
    )

    section = result.reload.snapshot.fetch("sections").sole
    expect(section).to include("kind" => "rich_text", "position" => 0, "visible" => true)
    expect(section.dig("translations", "en", "body")).to eq("Hello")
  end

  it "rejects published themes, foreign themes, and invalid snapshots" do
    published = store.storefront_themes.create!(
      name: "Live", catalog_key: "live", status: "published", published_at: Time.current,
      snapshot: snapshot_with([])
    )
    expect {
      described_class.call(store: store, theme: published, snapshot: snapshot_with([ rich_text_section ]))
    }.to raise_error(StorefrontThemes::UpdateSnapshot::PublishedTheme)

    foreign = Store.create!(slug: "snap-fx-#{SecureRandom.hex(4)}", name: "Foreign", currency: "MAD",
      storefront_enabled: true)
    foreign_theme = StorefrontThemes::Install.call(store: foreign, catalog_key: "minimal")
    expect {
      described_class.call(store: store, theme: foreign_theme, snapshot: snapshot_with([ rich_text_section ]))
    }.to raise_error(StorefrontThemes::UpdateSnapshot::StoreMismatch)

    expect {
      described_class.call(store: store, theme: theme, snapshot: { "sections" => "nope" })
    }.to raise_error(StorefrontThemes::UpdateSnapshot::InvalidSnapshot)

    expect {
      described_class.call(store: store, theme: theme,
        snapshot: snapshot_with([ rich_text_section("settings" => { "unknown" => "x" }) ]))
    }.to raise_error(StorefrontThemes::UpdateSnapshot::InvalidSnapshot, /unsupported settings/)
  end
end
