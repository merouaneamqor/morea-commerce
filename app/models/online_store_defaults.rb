# frozen_string_literal: true

# Default theme content: the home page sections, starter pages and menus.
# Built from the store's existing copy so installing changes nothing visible.
class OnlineStoreDefaults
  LOCALES = Morea::Locales::AVAILABLE.map(&:to_s).freeze

  attr_reader :store

  def initialize(store)
    @store = store
  end

  def install!
    Store.transaction do
      home_sections.each(&:save!) unless store.home_sections.exists?
      pages.each(&:save!) unless store.pages.exists?
      menu_items.each(&:save!) unless store.menu_items.exists?
    end
  end

  def home_sections
    featured_link = store.featured_product ? "product:#{store.featured_product.slug}" : "collections"
    manifesto = "/images/editorial/manifesto.jpg"

    [
      section("hero", { image_url: store.campaign_image, link: featured_link }) do |loc, st|
        { subheading: [ st&.campaign_title.presence || t(loc, "store.default_campaign_title"), st&.campaign_season.presence || "SS / 26" ].join(" · "),
          heading: st&.tagline.presence || t(loc, "store.tagline_fallback"),
          button_label: st&.campaign_cta.presence || t(loc, "store.default_campaign_cta") }
      end,
      section("ticker") do |loc, st|
        { body: [ t(loc, "landing.trust.delivery"), t(loc, "landing.trust.returns"), t(loc, "store.footer_tagline"),
                 st&.campaign_season.presence || "SS / 26" ].join("\n") }
      end,
      section("featured_collection", { collection_id: store.featured_collection_id&.to_s, limit: "4" }) do |loc, _|
        { heading: t(loc, "home.selection_title") }
      end,
      section("collection_list", { limit: "3" }) do |loc, _|
        { subheading: t(loc, "shop.collections"), heading: t(loc, "home.collections_title") }
      end,
      section("rich_text", { image_url: (manifesto if Rails.public_path.join(manifesto.delete_prefix("/")).exist?), link: featured_link }) do |loc, st|
        { subheading: t(loc, "landing.story_eyebrow"), body: st&.about,
          button_label: st&.campaign_cta.presence || t(loc, "store.default_campaign_cta") }
      end
    ].each_with_index { |s, i| s.position = i }
  end

  def pages
    phone = store.phone.presence
    email = store.email.presence
    contact = { "fr" => [ phone, email ].compact.join(" ou "), "en" => [ phone, email ].compact.join(" or "), "ar" => [ phone, email ].compact.join(" أو ") }

    [
      page("about", {
        "fr" => { title: "Notre histoire", body: store_text("fr", :about) },
        "en" => { title: "Our story", body: store_text("en", :about) },
        "ar" => { title: "قصتنا", body: store_text("ar", :about) }
      }),
      page("shipping", {
        "fr" => { title: "Livraison & paiement", body: "Nous livrons partout au Maroc.\n\nLe paiement se fait à la livraison. #{store_text("fr", :cod_note)}" },
        "en" => { title: "Shipping & payment", body: "We deliver across Morocco.\n\nYou pay on delivery. #{store_text("en", :cod_note)}" },
        "ar" => { title: "التوصيل والدفع", body: "نوصل إلى جميع أنحاء المغرب.\n\nالدفع عند الاستلام. #{store_text("ar", :cod_note)}" }
      }),
      page("returns", {
        "fr" => { title: "Retours", body: "Vous disposez de 7 jours après réception pour nous retourner un article.\n\nContactez-nous au #{contact["fr"]} pour organiser le retour." },
        "en" => { title: "Returns", body: "You have 7 days after delivery to return an item.\n\nContact us at #{contact["en"]} to arrange your return." },
        "ar" => { title: "الإرجاع", body: "لديكم 7 أيام بعد الاستلام لإرجاع أي قطعة.\n\nتواصلوا معنا على #{contact["ar"]} لترتيب الإرجاع." }
      })
    ]
  end

  def menu_items
    collection = store.featured_collection || store.collections.published.order(:position).first
    header = [
      [ "collections", ->(loc) { t(loc, "nav.shop") } ],
      ([ "collection:#{collection.slug}", ->(loc) { collection.translation_for(loc)&.name.presence || collection.name } ] if collection),
      [ "page:about", ->(loc) { { "fr" => "Notre histoire", "en" => "Our story", "ar" => "قصتنا" }[loc] } ]
    ].compact
    footer = [
      [ "page:shipping", ->(loc) { { "fr" => "Livraison & paiement", "en" => "Shipping & payment", "ar" => "التوصيل والدفع" }[loc] } ],
      [ "page:returns", ->(loc) { { "fr" => "Retours", "en" => "Returns", "ar" => "الإرجاع" }[loc] } ],
      [ "track", ->(loc) { t(loc, "nav.track_order") } ],
      [ "https://www.instagram.com/morea.style/", ->(_) { "Instagram" } ]
    ]

    { "header" => header, "footer" => footer }.flat_map do |menu, items|
      items.each_with_index.map do |(link, label), i|
        item = MenuItem.new(store_id: store.id, menu: menu, link: link, position: i)
        LOCALES.each { |loc| item.translations.build(locale: loc, label: label.call(loc)) }
        item
      end
    end
  end

  private

  def section(kind, settings = {})
    section = HomeSection.new(store_id: store.id, kind: kind, settings: settings.compact.transform_keys(&:to_s))
    LOCALES.each do |loc|
      section.translations.build(yield(loc, store.translation_for(loc)).merge(locale: loc))
    end
    section
  end

  def page(slug, translations)
    page = Page.new(store_id: store.id, slug: slug, published: true)
    translations.each { |loc, attrs| page.translations.build(attrs.merge(locale: loc)) }
    page
  end

  def store_text(locale, attr)
    store.translation_for(locale)&.public_send(attr).presence || store.translation_for(Morea::Locales::DEFAULT)&.public_send(attr)
  end

  def t(locale, key)
    I18n.t(key, locale: locale)
  end
end
