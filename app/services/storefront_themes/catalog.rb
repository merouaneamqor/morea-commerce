# frozen_string_literal: true

module StorefrontThemes
  class Catalog
    LOCALES = %w[fr en ar].freeze
    THEMES = {
      "atelier" => {
        "name" => "Atelier",
        "sections" => [
          { "kind" => "hero", "visible" => true, "settings" => { "link" => "collections" },
            "translations" => {
              "fr" => { "subheading" => "Nouvelle collection", "heading" => "Pensé pour le mouvement", "button_label" => "Découvrir" },
              "en" => { "subheading" => "New collection", "heading" => "Designed for movement", "button_label" => "Discover" },
              "ar" => { "subheading" => "مجموعة جديدة", "heading" => "مصمم للحركة", "button_label" => "اكتشف" }
            } },
          { "kind" => "ticker", "visible" => true, "settings" => {}, "translations" => {
            "fr" => { "body" => "Livraison partout au Maroc\nPaiement à la livraison" },
            "en" => { "body" => "Delivery across Morocco\nCash on delivery" },
            "ar" => { "body" => "التوصيل في جميع أنحاء المغرب\nالدفع عند الاستلام" }
          } },
          { "kind" => "featured_collection", "visible" => true, "settings" => { "limit" => "4" }, "translations" => {
            "fr" => { "subheading" => "La sélection", "heading" => "Pièces signatures" },
            "en" => { "subheading" => "The edit", "heading" => "Signature pieces" },
            "ar" => { "subheading" => "مختاراتنا", "heading" => "قطع مميزة" }
          } },
          { "kind" => "collection_list", "visible" => true, "settings" => { "limit" => "3" }, "translations" => {
            "fr" => { "subheading" => "Explorer", "heading" => "Nos collections" },
            "en" => { "subheading" => "Explore", "heading" => "Our collections" },
            "ar" => { "subheading" => "اكتشف", "heading" => "مجموعاتنا" }
          } },
          { "kind" => "rich_text", "visible" => true, "settings" => { "link" => "page:about" }, "translations" => {
            "fr" => { "subheading" => "Notre maison", "body" => "Des essentiels créés avec intention.", "button_label" => "Notre histoire" },
            "en" => { "subheading" => "Our house", "body" => "Essentials created with intention.", "button_label" => "Our story" },
            "ar" => { "subheading" => "علامتنا", "body" => "أساسيات صممت بعناية.", "button_label" => "قصتنا" }
          } }
        ]
      },
      "minimal" => {
        "name" => "Minimal",
        "sections" => [
          { "kind" => "hero", "visible" => true, "settings" => { "link" => "collections" }, "translations" => {
            "fr" => { "heading" => "L'essentiel, simplement", "button_label" => "Voir la boutique" },
            "en" => { "heading" => "Simply essential", "button_label" => "Shop now" },
            "ar" => { "heading" => "البساطة في الأساس", "button_label" => "تسوق الآن" }
          } },
          { "kind" => "featured_collection", "visible" => true, "settings" => { "limit" => "8" }, "translations" => {
            "fr" => { "heading" => "Sélection" }, "en" => { "heading" => "Featured" }, "ar" => { "heading" => "مختارات" }
          } },
          { "kind" => "rich_text", "visible" => true, "settings" => { "link" => "page:about" }, "translations" => {
            "fr" => { "body" => "Des pièces utiles, faites pour durer.", "button_label" => "En savoir plus" },
            "en" => { "body" => "Useful pieces, made to last.", "button_label" => "Learn more" },
            "ar" => { "body" => "قطع عملية مصممة لتدوم.", "button_label" => "اعرف المزيد" }
          } }
        ]
      }
    }.freeze

    class UnknownTheme < KeyError; end

    def self.all
      THEMES.map { |key, value| { key: key, name: value.fetch("name"), snapshot: value.deep_dup } }
    end

    def self.fetch(key)
      THEMES.fetch(key.to_s).deep_dup
    rescue KeyError
      raise UnknownTheme, "Unknown storefront theme: #{key}"
    end
  end
end
