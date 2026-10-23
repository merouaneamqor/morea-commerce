# frozen_string_literal: true

require Rails.root.join("lib/morea/our_story")

class UpdateOurStoryPage < ActiveRecord::Migration[8.1]
  def up
    Page.where(slug: "about").find_each do |page|
      Morea::OurStory::BODIES.each do |locale, body|
        translation = page.translations.find_or_initialize_by(locale: locale)
        translation.update!(title: Morea::OurStory::TITLES[locale], body: body)
      end
    end
  end

  def down; end
end
