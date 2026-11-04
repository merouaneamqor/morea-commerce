# frozen_string_literal: true

# The seller workspace shell (sidebar, header) and the copy of its pages, ported from seallo.
# Strings are written in French, as on seallo, and translated through the same dictionary.
module SellerHelper
  SELLER_DICTIONARY = JSON.parse(Rails.root.join("config/seller_dictionary.json").read).freeze

  # Words that exist only in Morea (seallo has no such page): [English, Arabic].
  SELLER_EXTRA = { "Comptabilité" => [ "Accounting", "المحاسبة" ] }.freeze

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
    "new" => [ "Nouvelle", "bg-[#ebe9fb] text-[#4b4fb0]" ],
    "confirmed" => [ "Confirmée", "bg-[#e4ecfb] text-[#3d63b8]" ],
    "postponed" => [ "Reportée", "bg-[#f1eee9] text-[#6f6967]" ],
    "unreachable" => [ "Injoignable", "bg-[#f1eee9] text-[#6f6967]" ],
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

  def seller_status_badge(status)
    SELLER_STATUS_BADGES[SELLER_BADGE_FOR_STATUS.fetch(status, status)] || [ status.to_s.humanize, "bg-[#f1eee9] text-[#6f6967]" ]
  end

  def seller_plan_label(store)
    return if store&.plan.blank?

    store.plan == "free" ? sl("Gratuit") : store.plan.capitalize
  end
end
