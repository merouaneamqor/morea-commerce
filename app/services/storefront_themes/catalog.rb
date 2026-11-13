# frozen_string_literal: true

module StorefrontThemes
  class Catalog
    LOCALES = Morea::Locales::AVAILABLE.map(&:to_s).freeze
    THEMES = {
      "atelier" => {
        "name" => "Atelier",
        "sections" => [
          { "kind" => "hero", "visible" => true, "settings" => { "link" => "collections" },
            "translations" => {
              "fr" => {
                "subheading" => "Nouvelle saison",
                "heading" => "Des pièces faites pour bouger",
                "body" => "Coupe nette, matière tenue, rythme du quotidien.",
                "button_label" => "Découvrir la collection"
              },
              "en" => {
                "subheading" => "New season",
                "heading" => "Pieces cut for movement",
                "body" => "Clean lines, held fabric, made for the day ahead.",
                "button_label" => "Discover the collection"
              },
              "es" => {
                "subheading" => "Nueva temporada",
                "heading" => "Piezas hechas para moverse",
                "body" => "Líneas limpias, tejido firme, para el ritmo del día.",
                "button_label" => "Descubrir la colección"
              },
              "ar" => {
                "subheading" => "موسم جديد",
                "heading" => "قطع صُممت للحركة",
                "body" => "خطوط واضحة، قماش متماسك، لإيقاع اليوم.",
                "button_label" => "اكتشف المجموعة"
              }
            } },
          { "kind" => "featured_collection", "visible" => true, "settings" => { "limit" => "4" }, "translations" => {
            "fr" => { "subheading" => "À regarder d’abord", "heading" => "Pièces signatures" },
            "en" => { "subheading" => "Start here", "heading" => "Signature pieces" },
            "es" => { "subheading" => "Empieza aquí", "heading" => "Piezas insignia" },
            "ar" => { "subheading" => "ابدأ من هنا", "heading" => "قطع مميزة" }
          } },
          { "kind" => "image_with_text", "visible" => true, "settings" => { "link" => "page:about", "image_position" => "left" }, "translations" => {
            "fr" => {
              "subheading" => "La maison",
              "heading" => "Un point de vue, tenu",
              "body" => "Chaque pièce part d’une matière, d’une coupe et d’un usage réel. L’essentiel, sans surplus.",
              "button_label" => "Notre histoire"
            },
            "en" => {
              "subheading" => "The house",
              "heading" => "A point of view, held",
              "body" => "Each piece starts from a fabric, a cut, and a real use. The essentials, nothing extra.",
              "button_label" => "Our story"
            },
            "es" => {
              "subheading" => "La casa",
              "heading" => "Un punto de vista, firme",
              "body" => "Cada pieza parte de un tejido, un corte y un uso real. Lo esencial, sin más.",
              "button_label" => "Nuestra historia"
            },
            "ar" => {
              "subheading" => "الدار",
              "heading" => "رؤية واضحة ومثبتة",
              "body" => "كل قطعة تبدأ من قماش وقصة واستخدام حقيقي. الأساسيات دون زيادة.",
              "button_label" => "قصتنا"
            }
          } },
          { "kind" => "collection_list", "visible" => true, "settings" => { "limit" => "3" }, "translations" => {
            "fr" => { "subheading" => "Explorer", "heading" => "Collections" },
            "en" => { "subheading" => "Explore", "heading" => "Collections" },
            "es" => { "subheading" => "Explorar", "heading" => "Colecciones" },
            "ar" => { "subheading" => "استكشف", "heading" => "المجموعات" }
          } },
          { "kind" => "rich_text", "visible" => true, "settings" => { "link" => "collections" }, "translations" => {
            "fr" => {
              "subheading" => "Commander",
              "body" => "Choisissez une pièce. Recevez-la. Payez à la livraison.",
              "button_label" => "Voir toute la sélection"
            },
            "en" => {
              "subheading" => "Order",
              "body" => "Choose a piece. Receive it. Pay on delivery.",
              "button_label" => "See the full edit"
            },
            "es" => {
              "subheading" => "Pedir",
              "body" => "Elige una pieza. Recíbela. Paga contra reembolso.",
              "button_label" => "Ver toda la selección"
            },
            "ar" => {
              "subheading" => "اطلب",
              "body" => "اختر قطعة. استلمها. ادفع عند الاستلام.",
              "button_label" => "عرض كل المختارات"
            }
          } }
        ]
      },
      "minimal" => {
        "name" => "Minimal",
        "sections" => [
          { "kind" => "hero", "visible" => true, "settings" => { "link" => "collections" }, "translations" => {
            "fr" => {
              "subheading" => "Essentiel",
              "heading" => "L'essentiel, tenu",
              "body" => "Peu de pièces, chacune utile et claire.",
              "button_label" => "Voir la boutique"
            },
            "en" => {
              "subheading" => "Essential",
              "heading" => "The essentials, held",
              "body" => "Few pieces, each useful and clear.",
              "button_label" => "Shop now"
            },
            "es" => {
              "subheading" => "Esencial",
              "heading" => "Lo esencial, claro",
              "body" => "Pocas piezas, cada una útil y clara.",
              "button_label" => "Ver la tienda"
            },
            "ar" => {
              "subheading" => "أساسي",
              "heading" => "الأساسيات، بوضوح",
              "body" => "قطع قليلة، كل واحدة مفيدة وواضحة.",
              "button_label" => "تسوق الآن"
            }
          } },
          { "kind" => "featured_collection", "visible" => true, "settings" => { "limit" => "8" }, "translations" => {
            "fr" => { "heading" => "Sélection" }, "en" => { "heading" => "Featured" }, "es" => { "heading" => "Selección" }, "ar" => { "heading" => "مختارات" }
          } },
          { "kind" => "rich_text", "visible" => true, "settings" => { "link" => "page:about" }, "translations" => {
            "fr" => { "body" => "Des pièces utiles, faites pour durer.", "button_label" => "En savoir plus" },
            "en" => { "body" => "Useful pieces, made to last.", "button_label" => "Learn more" },
            "es" => { "body" => "Piezas útiles, hechas para durar.", "button_label" => "Saber más" },
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
