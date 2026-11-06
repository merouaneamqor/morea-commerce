# frozen_string_literal: true

module DataProtection
  class Bootstrap
    COMPLIANCE_PAGES = {
      "privacy" => Morea::PrivacyPolicy,
      "terms" => Morea::TermsOfService,
      "cookies" => Morea::CookiePolicy
    }.freeze

    def self.install_for_store!(store)
      new(store).install!
    end

    def initialize(store)
      @store = store
    end

    def install!
      COMPLIANCE_PAGES.each_key { |slug| install_page!(slug) unless store.pages.exists?(slug: slug) }
      COMPLIANCE_PAGES.each { |slug, mod| install_footer_link!(slug, mod) unless footer_link_exists?(slug) }
    end

    private

    attr_reader :store

    def install_page!(slug)
      mod = COMPLIANCE_PAGES.fetch(slug)
      page = store.pages.build(slug: slug, published: true)
      mod::LOCALES.each do |locale|
        page.translations.build(
          locale: locale,
          title: mod.titles[locale],
          body: mod.body_for(store, locale: locale)
        )
      end
      page.save!
    end

    def install_footer_link!(slug, mod)
      position = store.menu_items.where(menu: "footer").maximum(:position).to_i + 1
      item = store.menu_items.build(menu: "footer", link: "page:#{slug}", position: position)
      mod::LOCALES.each do |locale|
        item.translations.build(locale: locale, label: mod.menu_labels[locale])
      end
      item.save!
    end

    def footer_link_exists?(slug)
      store.menu_items.where(menu: "footer", link: "page:#{slug}").exists?
    end
  end
end
