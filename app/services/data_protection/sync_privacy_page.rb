# frozen_string_literal: true

module DataProtection
  class SyncPrivacyPage
    def self.call(store)
      new(store).call
    end

    def initialize(store)
      @store = store
    end

    def call
      page = store.pages.find_by(slug: "privacy")
      return unless page

      Morea::PrivacyPolicy::LOCALES.each do |locale|
        translation = page.translations.find_or_initialize_by(locale: locale)
        translation.title = Morea::PrivacyPolicy.titles[locale]
        translation.body = Morea::PrivacyPolicy.body_for(store, locale: locale)
        translation.save!
      end
    end

    private

    attr_reader :store
  end
end
