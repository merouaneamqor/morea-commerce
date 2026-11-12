# frozen_string_literal: true

# The seller workspace shell (sidebar, header) and the copy of its pages, ported from seallo.
# Strings are written in French, as on seallo, and translated through the same dictionary.
module SellerHelper
  SELLER_DICTIONARY = JSON.parse(Rails.root.join("config/seller_dictionary.json").read).freeze

  # Words that exist only in Morea (seallo has no such page): [English, Arabic].
  SELLER_EXTRA = {
    "Comptabilité" => [ "Accounting", "المحاسبة" ],
    "Paliers de chiffre d'affaires" => [ "Revenue milestones", "مراحل رقم المعاملات" ],
    "Livré depuis le début" => [ "Delivered since the start", "المسلَّم منذ البداية" ],
    "Débutant" => [ "Beginner", "مبتدئ" ],
    "Distribution des commandes" => [ "Order distribution", "توزيع الطلبات" ],
    "Commandes de la période" => [ "Orders of the period", "طلبات الفترة" ],
    "Confirmation" => [ "Confirmation", "التأكيد" ],
    "Expédition" => [ "Shipping", "الشحن" ],
    "Programmées" => [ "Scheduled", "مجدولة" ],
    "Faux numéros" => [ "Wrong numbers", "أرقام خاطئة" ],
    "À expédier" => [ "To ship", "للشحن" ],
    "En transit" => [ "In transit", "في الطريق" ],
    "Problème" => [ "Problem", "مشكلة" ],
    "Meilleurs produits" => [ "Best products", "أفضل المنتجات" ],
    "Ventes livrées par produit, hors livraison" => [ "Delivered sales by product, delivery excluded", "المبيعات المسلّمة لكل منتج دون التوصيل" ],
    "Aucune vente livrée sur la période." => [ "No delivered sale in the period.", "لا مبيعات مسلّمة في الفترة." ],
    "commandes" => [ "orders", "طلبات" ],
    "Je suis ici" => [ "I'm here", "أنا هنا" ],
    "Je continue jusqu'à" => [ "I keep going to", "أواصل حتى" ],
    "Masquer les paliers" => [ "Hide the milestones", "إخفاء المراحل" ],
    "Afficher les paliers" => [ "Show the milestones", "إظهار المراحل" ],
    "Prochain palier" => [ "Next tier", "المرحلة التالية" ],
    "Palier maximal atteint" => [ "Top tier reached", "تم بلوغ أعلى مرحلة" ],
    "avant" => [ "to", "قبل" ],
    "Pionnier" => [ "Pioneer", "رائد" ],
    "Doyen" => [ "Veteran", "عميد" ],
    "Leader" => [ "Leader", "قائد" ],
    "Maître" => [ "Master", "أستاذ" ],
    "Légende" => [ "Legend", "أسطورة" ],
    "Titan" => [ "Titan", "عملاق" ],
    "Taux de confirmation" => [ "Confirmation rate", "نسبة التأكيد" ],
    "Panier moyen" => [ "Average basket", "متوسط السلة" ],
    "Taux de retour" => [ "Return rate", "نسبة الإرجاع" ],
    "retournées" => [ "returned", "مرتجعة" ],
    "Commandes livrées" => [ "Delivered orders", "الطلبات المسلّمة" ],
    "commandes livrées" => [ "delivered orders", "طلبات مسلّمة" ],
    "Toutes les commandes" => [ "All orders", "كل الطلبات" ],
    "Stock faible" => [ "Low stock", "مخزون منخفض" ],
    "Rupture" => [ "Out of stock", "نفد المخزون" ],
    "pcs" => [ "pcs", "قطعة" ],
    "Voir les produits" => [ "See products", "عرض المنتجات" ],
    "Aucun article sous le seuil." => [ "No article below the threshold.", "لا توجد منتجات تحت الحد." ],
    "Articles à" => [ "Articles at", "منتجات عند" ],
    "pièces ou moins" => [ "pieces or fewer", "قطع أو أقل" ],
    "confirmées" => [ "confirmed", "مؤكدة" ]
  }.freeze

  SELLER_ICONS = {
    home: '<path d="M3 10.5 12 3l9 7.5V20a1 1 0 0 1-1 1h-5v-6H9v6H4a1 1 0 0 1-1-1z"/>',
    orders: '<path d="M6 7h12l-1 13H7L6 7z"/><path d="M9 7a3 3 0 0 1 6 0"/>',
    phone: '<path d="M22 16.9v3a2 2 0 0 1-2.2 2 19.8 19.8 0 0 1-8.6-3.1 19.5 19.5 0 0 1-6-6A19.8 19.8 0 0 1 2.1 4.2 2 2 0 0 1 4.1 2h3a2 2 0 0 1 2 1.7c.1.9.4 1.8.7 2.7a2 2 0 0 1-.5 2.1L8 9.8a16 16 0 0 0 6 6l1.3-1.3a2 2 0 0 1 2.1-.4c.9.3 1.8.6 2.7.7a2 2 0 0 1 1.7 2z"/>',
    truck: '<path d="M3 6h11v10H3z"/><path d="M14 9h4l3 3v4h-7"/><circle cx="7" cy="17.5" r="1.8"/><circle cx="17" cy="17.5" r="1.8"/>',
    box: '<path d="m12 3 8 4.5v9L12 21l-8-4.5v-9z"/><path d="m4 7.5 8 4.5 8-4.5M12 12v9"/>',
    target: '<circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="5"/><circle cx="12" cy="12" r="1"/>',
    profit: '<path d="m3 17 6-6 4 4 8-8"/><path d="M15 7h6v6"/>',
    calculator: '<rect x="4" y="2" width="16" height="20" rx="2"/><path d="M8 6h8M16 14v4M8 10h.01M12 10h.01M16 10h.01M8 14h.01M12 14h.01M8 18h.01M12 18h.01"/>',
    clients: '<circle cx="9" cy="8" r="3.5"/><path d="M2.5 20a6.5 6.5 0 0 1 13 0"/><path d="M16 4.5a3.5 3.5 0 0 1 0 7M18 14a6.5 6.5 0 0 1 3.5 6"/>',
    chart: '<path d="M4 20V10M10 20V4M16 20v-7M22 20H2"/>',
    plug: '<path d="M9 2v6M15 2v6"/><path d="M6 8h12v3a6 6 0 0 1-12 0V8z"/><path d="M12 17v5"/>',
    team: '<circle cx="12" cy="8" r="4"/><path d="M4 21a8 8 0 0 1 16 0"/>',
    settings: '<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"/>',
    logout: '<path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><path d="m16 17 5-5-5-5M21 12H9"/>',
    clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
    check: '<circle cx="12" cy="12" r="9"/><path d="m8 12.5 2.8 2.8L16 9.5"/>',
    cart: '<circle cx="9" cy="20" r="1.5"/><circle cx="18" cy="20" r="1.5"/><path d="M3 4h2.5l2.2 11h10.3l2-8H6.5"/>',
    undo: '<path d="M9 14 4 9l5-5"/><path d="M4 9h10a6 6 0 0 1 0 12h-3"/>',
    cancel: '<circle cx="12" cy="12" r="9"/><path d="m9 9 6 6M15 9l-6 6"/>',
    ban: '<circle cx="12" cy="12" r="9"/><path d="M5.6 5.6l12.8 12.8"/>',
    wallet: '<rect x="3" y="6" width="18" height="13" rx="3"/><path d="M3 10h18"/><circle cx="16.5" cy="14.5" r="1"/>',
    alert: '<path d="M12 4 3 20h18L12 4z"/><path d="M12 10v4M12 17.5v.01"/>',
    lock: '<rect x="5" y="11" width="14" height="9" rx="2"/><path d="M8 11V8a4 4 0 0 1 8 0v3"/>',
    flag: '<path d="M5 21V4"/><path d="M5 5h11l-2 4 2 4H5"/>',
    search: '<circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/>',
    menu: '<path d="M4 7h16M4 12h16M4 17h16"/>'
  }.freeze

  # [key, icon, label, link]; no link means "coming soon".
  SELLER_MENU = [
    [ "dashboard", :home, "Tableau de bord", "/dashboard" ],
    [ "orders", :orders, "Commandes", "/commandes" ],
    [ "confirmation", :phone, "Confirmation", "/confirmation" ],
    [ "stats", :chart, "Mes statistiques", "/mes-statistiques" ],
    [ "clients", :clients, "Clients", "/clients" ],
    [ "delivery", :truck, "Livraison", "/livraison" ],
    [ "products", :box, "Produits", "/produits" ],
    [ "ads", :target, "Publicités", nil ],
    [ "accounting", :calculator, "Comptabilité", "/comptabilite" ],
    [ "team", :team, "Équipe", "/equipe" ],
    [ "integrations", :plug, "Intégrations API", "/integrations" ]
  ].freeze

  # Which menu entry a controller belongs to, so the pages not yet ported still highlight their entry.
  SELLER_ACTIVE_BY_CONTROLLER = {
    "dashboard" => "dashboard", "orders" => "orders", "confirmations" => "confirmation", "my_stats" => "stats",
    "customers" => "clients", "delivery" => "delivery", "products" => "products", "variants" => "products",
    "inventory" => "products", "users" => "team", "agent_api" => "integrations", "store_connections" => "integrations",
    "seallo_connections" => "integrations", "woocommerce_connections" => "integrations", "meta_ads" => "integrations",
    "accounting" => "accounting"
  }.freeze

  SELLER_STATUS_BADGES = {
    "new" => [ "Nouvelle", "bg-[#ebe9fb] text-[#4b4b50]" ],
    "confirmed" => [ "Confirmée", "bg-[#e4ecfb] text-[#4b4b50]" ],
    "postponed" => [ "Reportée", "bg-[#efeff3] text-[#6e6e73]" ],
    "unreachable" => [ "Injoignable", "bg-[#efeff3] text-[#6e6e73]" ],
    "cancelled" => [ "Annulée", "bg-[#fbe7ea] text-[#b4344e]" ],
    "shipped" => [ "En cours", "bg-[#fcf0dc] text-[#9a6412]" ],
    "delivered" => [ "Livrée", "bg-[#e3f3e8] text-[#2f7a4a]" ],
    "returned" => [ "Retournée", "bg-[#fbe7ea] text-[#b4344e]" ]
  }.freeze

  # Morea has finer-grained order statuses than seallo; they are shown with the nearest seallo badge.
  SELLER_BADGE_FOR_STATUS = {
    "preparing" => "confirmed", "awaiting_pickup" => "shipped", "picked_up" => "shipped", "in_transit" => "shipped",
    "out_for_delivery" => "shipped", "address_issue" => "postponed"
  }.freeze

  def sl(french)
    return french if I18n.locale == :fr

    pair = SELLER_DICTIONARY[french] || SELLER_EXTRA[french]
    return french unless pair

    I18n.locale == :en ? pair[0] : pair[1]
  end

  def seller_icon(name, size: 18)
    tag.svg(SELLER_ICONS.fetch(name).html_safe, viewBox: "0 0 24 24", "aria-hidden": "true", focusable: "false",
      class: "shrink-0 fill-none stroke-current [stroke-linecap:round] [stroke-linejoin:round] [stroke-width:1.8]", style: "width:#{size}px;height:#{size}px")
  end

  # Amount in whole currency units (up to two decimals), kept left-to-right inside Arabic text.
  def seller_number(value)
    text = number_with_precision(value, precision: 2, strip_insignificant_zeros: true, delimiter: " ", separator: ",")
    "⁦#{text}⁩"
  end

  # Whole currency units (no decimals), kept left-to-right inside Arabic text.
  def seller_money(cents, currency)
    "⁦#{number_with_delimiter(cents.to_i.fdiv(100).round, delimiter: " ")} #{currency}⁩"
  end

  def seller_menu(user)
    agent = user&.confirmation_agent_view?
    SELLER_MENU.select { |key, *| agent ? %w[confirmation stats orders].include?(key) : key != "stats" }
  end

  def seller_active_key
    SELLER_ACTIVE_BY_CONTROLLER[controller_name]
  end

  # Soft tints of the dashboard figures: card background, border, icon chip, icon colour. Colours only.
  DASHBOARD_TONES = {
    "neutral" => { card: "bg-white border-[#e0e0e5]", chip: "bg-[#efeff3] text-[#1c1c1e]" },
    "green" => { card: "bg-[#f1faf5] border-[#d4eedd]", chip: "bg-[#dcf2e5] text-[#2f7a4a]" },
    "blue" => { card: "bg-[#f2f7fd] border-[#d8e6f6]", chip: "bg-[#dfecfa] text-[#2f6fb5]" },
    "amber" => { card: "bg-[#fff8ea] border-[#f3e3bf]", chip: "bg-[#fcebc6] text-[#a8690d]" },
    "red" => { card: "bg-[#fef2f3] border-[#f5d7db]", chip: "bg-[#fbdfe2] text-[#b4344e]" },
    "gray" => { card: "bg-[#f6f6f8] border-[#e3e3e8]", chip: "bg-[#e9e9ee] text-[#636366]" },
    "ink" => { card: "bg-[#f6f6f8] border-[#e3e3e8]", chip: "bg-[#1c1c1e] text-white" },
    "dark" => { card: "bg-[#1c1c1e] border-transparent text-white", chip: "bg-white/12 text-white" }
  }.freeze

  def dashboard_tone(name)
    DASHBOARD_TONES.fetch(name.to_s, DASHBOARD_TONES["neutral"])
  end

  def seller_status_badge(status)
    SELLER_STATUS_BADGES[SELLER_BADGE_FOR_STATUS.fetch(status, status)] || [ status.to_s.humanize, "bg-[#efeff3] text-[#6e6e73]" ]
  end

  def seller_plan_label(store)
    return if store&.plan.blank?

    store.plan == "free" ? sl("Gratuit") : store.plan.capitalize
  end
end
