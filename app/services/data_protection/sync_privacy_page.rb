# frozen_string_literal: true

module DataProtection
  class SyncPrivacyPage
    PAGE_MODULES = {
      "privacy" => Morea::PrivacyPolicy,
      "terms" => Morea::TermsOfService,
      "cookies" => Morea::CookiePolicy
    }.freeze

    def self.call(store)
      new(store).call
    end

    def initialize(store)
      @store = store
    end

    def call
      PAGE_MODULES.each do |slug, mod|
        page = store.pages.find_by(slug: slug)
        next unless page

        mod::LOCALES.each do |locale|
          translation = page.translations.find_or_initialize_by(locale: locale)
          translation.title = mod.titles[locale]
          translation.body = mod.body_for(store, locale: locale)
          translation.save!
        end
      end
    end

    private

    attr_reader :store
  end
end
