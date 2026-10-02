# frozen_string_literal: true

# Images now come only from admin uploads (Cloudinary): drop the paths to the
# files that used to live in public/images, and upload the campaign photo as
# the home hero so the home page doesn't go blank.
class ClearHardcodedImages < ActiveRecord::Migration[8.1]
  HERO_PHOTO = Rails.root.join("db/data/campaign-hero.jpg")

  def up
    execute "UPDATE products SET image_url = NULL WHERE image_url LIKE '/images/%'"
    execute "UPDATE products SET detail_image_url = NULL WHERE detail_image_url LIKE '/images/%'"
    execute "UPDATE stores SET campaign_image_url = NULL WHERE campaign_image_url LIKE '/images/%'"
    execute "UPDATE home_sections SET settings = settings - 'image_url' WHERE settings->>'image_url' LIKE '/images/%'"

    return unless HERO_PHOTO.exist?

    HomeSection.reset_column_information
    HomeSection.where(kind: "hero").order(:position).group_by(&:store_id).each_value do |(hero, *)|
      next if hero.image.attached?

      hero.image.attach(io: HERO_PHOTO.open, filename: "campaign-hero.jpg", content_type: "image/jpeg")
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
