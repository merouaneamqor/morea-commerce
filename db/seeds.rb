# frozen_string_literal: true

puts "Seeding Morea Commerce..."

OrderItem.delete_all
InventoryMovement.delete_all
Order.delete_all
CartItem.delete_all
Cart.delete_all
Address.delete_all
Customer.delete_all
CollectionProduct.delete_all
ProductVariant.delete_all
ProductTranslation.delete_all
Product.delete_all
CollectionTranslation.delete_all
Collection.delete_all
StoreTranslation.delete_all

user = User.find_or_initialize_by(email: "admin@morea.website")
user.name = "Morea Admin"
user.password = "morea123"
user.password_confirmation = "morea123"
user.admin = true
user.save!
User.where(email: "admin@maison.ma").find_each(&:destroy)

store = Store.find_or_initialize_by(slug: "morea")
store.assign_attributes(
  name: "Morea",
  phone: "0522000000",
  email: "hello@morea.website",
  currency: "MAD",
  campaign_image_url: "https://images.unsplash.com/photo-1518310383802-640c2de311b2?auto=format&fit=crop&w=2400&q=80"
)
store.save!
Store.where.not(id: store.id).find_each(&:destroy)

store.translations.destroy_all
[
  {
    locale: "fr",
    tagline: "L'ensemble de sport pudique.",
    about: "Morea conçoit des ensembles de sport pudiques pour femmes actives — confort, style, performance et couverture qui accompagne le mouvement.",
    cod_label: "Paiement à la livraison",
    cod_note: "Aucun compte requis. Nous confirmons par téléphone, puis livrons partout au Maroc.",
    campaign_title: "Nouvelle collection",
    campaign_season: "SS / 26",
    campaign_cta: "Découvrir Morea"
  },
  {
    locale: "en",
    tagline: "The Modest Sportswear Set.",
    about: "Morea designs complete modest sportswear sets for active women — comfort, style, performance, and coverage that moves with you.",
    cod_label: "Cash on delivery",
    cod_note: "No account required. We confirm by phone, then deliver across Morocco.",
    campaign_title: "New Collection",
    campaign_season: "SS / 26",
    campaign_cta: "Discover Morea"
  },
  {
    locale: "ar",
    tagline: "طقم الرياضة المحتشم.",
    about: "تصمم موريا أطقم رياضية محتشمة كاملة للنساء النشيطات — راحة وأناقة وأداء وتغطية تتحرك معك.",
    cod_label: "الدفع عند الاستلام",
    cod_note: "لا حاجة لحساب. نؤكد عبر الهاتف ثم نوصل في جميع أنحاء المغرب.",
    campaign_title: "مجموعة جديدة",
    campaign_season: "SS / 26",
    campaign_cta: "اكتشفوا موريا"
  }
].each { |attrs| store.translations.create!(attrs) }

def create_collection!(store, slug:, position:, translations:)
  collection = store.collections.create!(
    slug: slug,
    name: translations.fetch("fr").fetch(:name),
    published: true,
    position: position
  )
  collection.translations.destroy_all
  translations.each do |locale, attrs|
    collection.translations.create!(attrs.merge(locale: locale))
  end
  collection
end

essentials = create_collection!(
  store,
  slug: "essentials",
  position: 1,
  translations: {
    "fr" => { name: "Essentiels", subtitle: "Le mouvement du quotidien, entièrement couvert", description: "Pièces fondatrices et ensembles complets pour l'entraînement, la marche et la vie de tous les jours." },
    "en" => { name: "Essentials", subtitle: "Everyday movement, fully covered", description: "Foundational pieces and complete sets for training, walking, and daily life." },
    "ar" => { name: "الأساسيات", subtitle: "حركة يومية بتغطية كاملة", description: "قطع أساسية وأطقم كاملة للتدريب والمشي والحياة اليومية." }
  }
)

premium = create_collection!(
  store,
  slug: "premium",
  position: 2,
  translations: {
    "fr" => { name: "Premium", subtitle: "Performance pudique élevée", description: "Tissus raffinés et silhouettes plus discrètes pour les femmes qui veulent présence et aisance." },
    "en" => { name: "Premium", subtitle: "Elevated modest performance", description: "Refined fabrics and quieter silhouettes for women who want both presence and ease." }
  }
)

casual = create_collection!(
  store,
  slug: "casual",
  position: 3,
  translations: {
    "fr" => { name: "Casual", subtitle: "Jours doux, couverture forte", description: "Couches pudiques détendues pour les week-ends et les échauffements." },
    "en" => { name: "Casual", subtitle: "Soft days, strong coverage", description: "Relaxed modest layers for weekends and warm-ups." }
  }
)

catalog = [
  {
    slug: "essential-set",
    price_dh: 899,
    compare_at_dh: 999,
    stock: 24,
    featured: true,
    image_url: "https://images.unsplash.com/photo-1518310383802-640c2de311b2?auto=format&fit=crop&w=1600&q=80",
    detail_image_url: "https://images.unsplash.com/photo-1571019614242-c5c5dee9f50b?auto=format&fit=crop&w=1600&q=80",
    collections: [essentials, premium],
    translations: {
      "fr" => {
        name: "L'ensemble essentiel",
        short_description: "Un ensemble de sport pudique complet — composé, couvert, prêt à bouger.",
        story: "Morea est née d'une idée : le sportswear doit permettre de s'entraîner entièrement couverte sans se sentir freinée. L'ensemble essentiel, c'est cette idée rendue tangible.",
        material: "Jersey stretch respirant au toucher doux brossé. Opaque en mouvement. Léger sur la peau.",
        fit: "Décontracté sur le corps avec une ligne nette. Conçu pour effleurer, pas pour coller. Disponible du S au XL.",
        movement: "Stretch quatre directions qui tient lors des extensions, fentes et longues marches. La couverture reste en place.",
        dimensions: "Ensemble haut + bas. Tailles S–XL",
        origin: "Conçu pour le Maroc",
        care: "Lavage machine à froid, cycle délicat. Séchage à l'air. Ne pas blanchir."
      },
      "en" => {
        name: "The Essential Set",
        short_description: "A complete modest sportswear set — composed, covered, ready to move.",
        story: "Morea began with one idea: activewear should let you train fully covered without feeling held back. The Essential Set is that idea made tangible — coordinated pieces that feel intentional together and effortless alone.",
        material: "Breathable stretch jersey with a soft brushed hand-feel. Opaque in motion. Light against the skin.",
        fit: "Relaxed through the body with a clean line. Designed to skim, not cling. Available in S–XL.",
        movement: "Four-way stretch that holds through reaches, lunges, and long walks. Coverage stays put.",
        dimensions: "Set includes top + bottom. Sizes S–XL",
        origin: "Designed for Morocco",
        care: "Machine wash cold, gentle cycle. Hang dry. Do not bleach."
      },
      "ar" => {
        name: "الطقم الأساسي",
        short_description: "طقم رياضي محتشم كامل — متناسق، مغطى، جاهز للحركة.",
        story: "بدأت موريا بفكرة واحدة: يجب أن يسمح لك اللباس الرياضي بالتدرب بتغطية كاملة دون شعور بالتقييد. الطقم الأساسي هو هذه الفكرة وقد صارت ملموسة.",
        material: "جيرسي مطاطي قابل للتنفس بملمس ناعم. غير شفاف أثناء الحركة. خفيف على البشرة.",
        fit: "مريح على الجسم بخط نظيف. مصمم ليلامس دون أن يلتصق. متوفر من S إلى XL.",
        movement: "تمدد رباعي الاتجاهات يثبت أثناء التمدد والطعنات والمشي الطويل. التغطية تبقى في مكانها.",
        dimensions: "الطقم يشمل أعلى وأسفل. المقاسات S–XL",
        origin: "مصمم للمغرب",
        care: "غسيل بارد بلطف. تجفيف بالتعليق. لا تبييض."
      }
    },
    variants: [
      { name: "S / Black", option1_name: "Size", option1_value: "S", option2_name: "Color", option2_value: "Black", stock: 6 },
      { name: "M / Black", option1_name: "Size", option1_value: "M", option2_name: "Color", option2_value: "Black", stock: 8 },
      { name: "L / Black", option1_name: "Size", option1_value: "L", option2_name: "Color", option2_value: "Black", stock: 6 },
      { name: "XL / Black", option1_name: "Size", option1_value: "XL", option2_name: "Color", option2_value: "Black", stock: 4 },
      { name: "M / Blush", option1_name: "Size", option1_value: "M", option2_name: "Color", option2_value: "Blush", stock: 4 }
    ]
  },
  {
    slug: "longline-performance-top",
    price_dh: 349,
    stock: 40,
    image_url: "https://images.unsplash.com/photo-1544966503-7cc5ac882d5f?auto=format&fit=crop&w=1600&q=80",
    collections: [essentials, casual],
    translations: {
      "fr" => {
        name: "Top performance longline",
        short_description: "Couverture allongée, stretch doux, à superposer ou porter seul.",
        story: "Coupe plus longue sur les hanches pour bouger, tendre et s'entraîner sans ajuster.",
        material: "Tricot stretch à séchage rapide.",
        fit: "Silhouette longline jusqu'à mi-hanche. Épaule douce, ourlet net.",
        movement: "Reste ancré lors des extensions et échauffements.",
        dimensions: "Tailles S–XL",
        origin: "Conçu pour le Maroc",
        care: "Lavage à froid. Ne pas repasser l'impression."
      },
      "en" => {
        name: "Longline Performance Top",
        short_description: "Extended coverage, soft stretch, made to layer or stand alone.",
        story: "Cut longer through the hips so you can move, reach, and train without adjusting.",
        material: "Moisture-wicking stretch knit.",
        fit: "Longline silhouette hitting mid-hip. Soft shoulder, clean hem.",
        movement: "Stays anchored through overhead reaches and warm-ups.",
        dimensions: "Sizes S–XL",
        origin: "Designed for Morocco",
        care: "Wash cold. Do not iron print."
      }
    },
    variants: [
      { name: "S", option1_name: "Size", option1_value: "S", stock: 10 },
      { name: "M", option1_name: "Size", option1_value: "M", stock: 14 },
      { name: "L", option1_name: "Size", option1_value: "L", stock: 10 },
      { name: "XL", option1_name: "Size", option1_value: "XL", stock: 6 }
    ]
  },
  {
    slug: "wide-leg-motion-pant",
    price_dh: 429,
    stock: 28,
    image_url: "https://images.unsplash.com/photo-1506629082955-511b1aa7845a?auto=format&fit=crop&w=1600&q=80",
    collections: [essentials, premium],
    translations: {
      "fr" => {
        name: "Pantalon motion wide-leg",
        short_description: "Couverture longueur totale avec une jambe fluide qui garde sa structure.",
        story: "Conçu pour marcher, s'étirer et voyager — longueur pudique avec de l'air pour respirer.",
        material: "Twill technique doux avec stretch léger.",
        fit: "Taille haute. Jambe large. Longueur cheville.",
        movement: "Foulée fluide sans coller. Structure là où il faut.",
        dimensions: "Tailles S–XL",
        origin: "Conçu pour le Maroc",
        care: "Lavage machine à froid. Repassage doux si besoin."
      },
      "en" => {
        name: "Wide-Leg Motion Pant",
        short_description: "Full-length coverage with a fluid wide leg that still holds structure.",
        story: "Designed for walking, stretching, and travel days — modest length with room to breathe.",
        material: "Soft technical twill with gentle stretch.",
        fit: "High rise. Wide leg. Full ankle length.",
        movement: "Fluid stride without cling. Structure where you need it.",
        dimensions: "Sizes S–XL",
        origin: "Designed for Morocco",
        care: "Machine wash cold. Low iron if needed."
      }
    }
  },
  {
    slug: "sports-hijab",
    price_dh: 199,
    stock: 60,
    image_url: "https://images.unsplash.com/photo-1601925260368-ae2f83cf8b7f?auto=format&fit=crop&w=1600&q=80",
    collections: [essentials],
    translations: {
      "fr" => {
        name: "Hijab sport",
        short_description: "Sûr, respirant, conçu pour rester en place pendant les échauffements et séances.",
        story: "Un hijab sport doit disparaître dans la séance — assez léger pour respirer, assez stable pour l'oublier.",
        material: "Jersey respirant avec stretch doux.",
        fit: "Taille unique. Couverture ajustable.",
        movement: "Reste stable lors des virages et changements de rythme.",
        origin: "Conçu pour le Maroc",
        care: "Lavage à froid. Séchage à l'air."
      },
      "en" => {
        name: "Sports Hijab",
        short_description: "Secure, breathable, built to stay put through warm-ups and workouts.",
        story: "A sports hijab should disappear into the session — light enough to breathe, stable enough to forget.",
        material: "Breathable jersey with soft stretch.",
        fit: "One size. Adjustable coverage.",
        movement: "Stays secure through turns and pace changes.",
        origin: "Designed for Morocco",
        care: "Wash cold. Hang dry."
      },
      "ar" => {
        name: "حجاب رياضي",
        short_description: "ثابت، قابل للتنفس، يبقى في مكانه أثناء الإحماء والتمارين.",
        story: "يجب أن يختفي الحجاب الرياضي في الجلسة — خفيف بما يكفي للتنفس، ثابت بما يكفي لنسيانه.",
        material: "جيرسي قابل للتنفس بتمدد ناعم.",
        fit: "مقاس واحد. تغطية قابلة للتعديل.",
        movement: "يثبت أثناء الالتفاف وتغيير الإيقاع.",
        origin: "مصمم للمغرب",
        care: "غسيل بارد. تجفيف بالتعليق."
      }
    },
    variants: [
      { name: "Blush", option2_name: "Color", option2_value: "Blush", stock: 20 },
      { name: "Sand", option2_name: "Color", option2_value: "Sand", stock: 20 },
      { name: "Ink", option2_name: "Color", option2_value: "Ink", stock: 20 }
    ]
  },
  {
    slug: "oversized-studio-jacket",
    price_dh: 599,
    stock: 18,
    image_url: "https://images.unsplash.com/photo-1556821840-3a63f95609a7?auto=format&fit=crop&w=1600&q=80",
    collections: [premium, casual],
    translations: {
      "fr" => {
        name: "Veste studio oversized",
        short_description: "Une couche légère pour avant et après — longueur pudique, lignes nettes.",
        story: "La pièce que l'on enfile en quittant le studio. Structure douce, sans bruit, couverture totale.",
        material: "Molleton brossé léger.",
        fit: "Oversize. Longueur mi-cuisse.",
        movement: "Facile par-dessus les ensembles. Épaules libres.",
        dimensions: "Tailles S–L",
        origin: "Conçu pour le Maroc",
        care: "Lavage à froid envers dehors."
      },
      "en" => {
        name: "Oversized Studio Jacket",
        short_description: "A light layer for before and after — modest length, clean lines.",
        story: "The piece you throw on leaving the studio. Soft structure, no noise, full coverage.",
        material: "Lightweight brushed fleece.",
        fit: "Oversized. Mid-thigh length.",
        movement: "Easy over sets. Unrestricted shoulders.",
        dimensions: "Sizes S–L",
        origin: "Designed for Morocco",
        care: "Wash cold inside out."
      }
    }
  },
  {
    slug: "soft-day-set",
    price_dh: 699,
    stock: 15,
    image_url: "https://images.unsplash.com/photo-1515886657613-9f3515b0c78f?auto=format&fit=crop&w=1600&q=80",
    collections: [casual],
    translations: {
      "fr" => {
        name: "Ensemble Soft Day",
        short_description: "Une silhouette plus douce pour les jours lents — toujours couverte, toujours considérée.",
        story: "Tous les jours ne sont pas des jours d'entraînement. Soft Day est pour les marches, les courses et les heures entre.",
        material: "Stretch mélange coton.",
        fit: "Haut et bas détendus. Drapé doux.",
        movement: "Aisance sans hâte pour le quotidien.",
        dimensions: "Tailles S–L",
        origin: "Conçu pour le Maroc",
        care: "Lavage délicat. Remettre en forme encore humide."
      },
      "en" => {
        name: "Soft Day Set",
        short_description: "A softer silhouette for slower days — still covered, still considered.",
        story: "Not every day is a training day. Soft Day is for walks, errands, and the hours between.",
        material: "Cotton-blend stretch.",
        fit: "Relaxed top and bottom. Soft drape.",
        movement: "Unhurried ease for daily wear.",
        dimensions: "Sizes S–L",
        origin: "Designed for Morocco",
        care: "Gentle wash. Reshape while damp."
      }
    }
  },
  {
    slug: "premium-training-set",
    price_dh: 999,
    stock: 10,
    image_url: "https://images.unsplash.com/photo-1594381898411-846e7d193883?auto=format&fit=crop&w=1600&q=80",
    collections: [premium],
    translations: {
      "fr" => {
        name: "Ensemble training premium",
        short_description: "Tissu haute performance, branding discret, couverture pudique complète.",
        story: "Pour les femmes qui s'entraînent sérieusement et s'habillent avec intention. Moins de pièces. De meilleures.",
        material: "Tricot technique performance à stretch quatre directions.",
        fit: "Précis sur le corps sans compression théâtrale.",
        movement: "Conçu pour les blocs d'entraînement — stable, respirant, opaque.",
        dimensions: "Tailles S–L",
        origin: "Conçu pour le Maroc",
        care: "Lavage à froid. Pas d'adoucissant."
      },
      "en" => {
        name: "Premium Training Set",
        short_description: "Higher-performance fabric, quieter branding, complete modest coverage.",
        story: "For women who train seriously and dress with intention. Fewer pieces. Better ones.",
        material: "Technical performance knit with four-way stretch.",
        fit: "Precise through the body without compression drama.",
        movement: "Built for training blocks — stable, breathable, opaque.",
        dimensions: "Sizes S–L",
        origin: "Designed for Morocco",
        care: "Wash cold. No fabric softener."
      }
    },
    variants: [
      { name: "S / Ink", option1_name: "Size", option1_value: "S", option2_name: "Color", option2_value: "Ink", stock: 3 },
      { name: "M / Ink", option1_name: "Size", option1_value: "M", option2_name: "Color", option2_value: "Ink", stock: 4 },
      { name: "L / Ink", option1_name: "Size", option1_value: "L", option2_name: "Color", option2_value: "Ink", stock: 3 }
    ]
  }
]

catalog.each_with_index do |attrs, index|
  collections = attrs.delete(:collections) || []
  variants = attrs.delete(:variants) || []
  translations = attrs.delete(:translations) || {}
  price_dh = attrs.delete(:price_dh)
  compare_at_dh = attrs.delete(:compare_at_dh)
  fr = translations.fetch("fr")

  product = store.products.create!(
    attrs.merge(
      name: fr.fetch(:name),
      short_description: fr[:short_description],
      story: fr[:story],
      material: fr[:material],
      fit: fr[:fit],
      movement: fr[:movement],
      dimensions: fr[:dimensions],
      origin: fr[:origin],
      care: fr[:care],
      price_cents: price_dh * 100,
      compare_at_cents: compare_at_dh ? compare_at_dh * 100 : nil,
      status: "active",
      position: index,
      currency: "MAD",
      track_inventory: true
    )
  )

  # create! already wrote FR via name= — replace with explicit locales
  product.translations.destroy_all
  translations.each do |locale, tattrs|
    product.translations.create!(tattrs.merge(locale: locale))
  end

  collections.each do |col|
    CollectionProduct.create!(collection: col, product: product)
  end

  variants.each do |variant_attrs|
    product.product_variants.create!(variant_attrs.merge(active: true, name: variant_attrs[:name]))
  end
end

featured = store.products.find_by!(slug: "essential-set")
store.update!(featured_product: featured, featured_collection: essentials)

puts "Admin: admin@morea.website / morea123"
puts "Store: #{store.name} — #{store.products.count} products — locales fr/en/ar"
puts "Done."
