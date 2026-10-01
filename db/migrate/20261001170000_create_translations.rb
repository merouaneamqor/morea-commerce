# frozen_string_literal: true

class CreateTranslations < ActiveRecord::Migration[8.1]
  def up
    create_table :product_translations do |t|
      t.references :product, null: false, foreign_key: true
      t.string :locale, null: false
      t.string :name
      t.text :short_description
      t.text :story
      t.text :material
      t.text :fit
      t.text :movement
      t.text :dimensions
      t.string :origin
      t.text :care
      t.string :seo_title
      t.string :seo_description
      t.timestamps
    end
    add_index :product_translations, %i[product_id locale], unique: true

    create_table :collection_translations do |t|
      t.references :collection, null: false, foreign_key: true
      t.string :locale, null: false
      t.string :name
      t.string :subtitle
      t.text :description
      t.timestamps
    end
    add_index :collection_translations, %i[collection_id locale], unique: true

    create_table :store_translations do |t|
      t.references :store, null: false, foreign_key: true
      t.string :locale, null: false
      t.string :tagline
      t.text :about
      t.string :cod_label
      t.text :cod_note
      t.string :campaign_title
      t.string :campaign_season
      t.string :campaign_cta
      t.timestamps
    end
    add_index :store_translations, %i[store_id locale], unique: true

    backfill_translations
  end

  def down
    drop_table :store_translations
    drop_table :collection_translations
    drop_table :product_translations
  end

  private

  def backfill_translations
    say_with_time "Backfilling product translations (fr + en)" do
      execute <<~SQL.squish
        INSERT INTO product_translations (
          product_id, locale, name, short_description, story, material, fit, movement,
          dimensions, origin, care, seo_title, seo_description, created_at, updated_at
        )
        SELECT
          id, locale, name, short_description, story, material, fit, movement,
          dimensions, origin, care, seo_title, seo_description, NOW(), NOW()
        FROM products
        CROSS JOIN (VALUES ('fr'), ('en')) AS locales(locale)
      SQL
    end

    say_with_time "Backfilling collection translations (fr + en)" do
      execute <<~SQL.squish
        INSERT INTO collection_translations (
          collection_id, locale, name, subtitle, description, created_at, updated_at
        )
        SELECT
          id, locale, name, subtitle, description, NOW(), NOW()
        FROM collections
        CROSS JOIN (VALUES ('fr'), ('en')) AS locales(locale)
      SQL
    end

    say_with_time "Backfilling store translations (fr + en)" do
      execute <<~SQL.squish
        INSERT INTO store_translations (
          store_id, locale, tagline, about, cod_label, cod_note,
          campaign_title, campaign_season, campaign_cta, created_at, updated_at
        )
        SELECT
          id, locale, tagline, about, cod_label, cod_note,
          campaign_title, campaign_season, campaign_cta, NOW(), NOW()
        FROM stores
        CROSS JOIN (VALUES ('fr'), ('en')) AS locales(locale)
      SQL
    end
  end
end
