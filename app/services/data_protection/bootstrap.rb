# frozen_string_literal: true

module DataProtection
  class Bootstrap
    def self.install_for_store!(store)
      new(store).install!
    end

    def initialize(store)
      @store = store
    end

    def install!
      install_page! unless store.pages.exists?(slug: "privacy")
      install_footer_link! unless footer_link_exists?
    end

    private

    attr_reader :store

    def install_page!
      page = store.pages.build(slug: "privacy", published: true)
      Morea::PrivacyPolicy::LOCALES.each do |locale|
        page.translations.build(
          locale: locale,
          title: Morea::PrivacyPolicy.titles[locale],
          body: Morea::PrivacyPolicy.body_for(store, locale: locale)
        )
      end
      page.save!
    end

    def install_footer_link!
      position = store.menu_items.where(menu: "footer").maximum(:position).to_i + 1
      item = store.menu_items.build(menu: "footer", link: "page:privacy", position: position)
      Morea::PrivacyPolicy::LOCALES.each do |locale|
        item.translations.build(locale: locale, label: Morea::PrivacyPolicy.menu_labels[locale])
      end
      item.save!
    end

    def footer_link_exists?
      store.menu_items.where(menu: "footer", link: "page:privacy").exists?
    end
  end
end
