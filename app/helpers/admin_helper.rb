module AdminHelper
  def admin_language_switch_path(locale)
    if controller_path == "platform_oauth/authorizations"
      return platform_oauth_authorize_path(ticket: params[:ticket].presence || @ticket, locale: locale)
    end

    if controller_path == "admin/seallo_connections"
      return "#{admin_seallo_connect_path}?#{ { locale: locale }.to_query}"
    end

    path = if !request.get? && action_name.in?(%w[create update])
      target = if action_name == "create"
        "new"
      elsif controller_path == "admin/store_connections"
        "show"
      else
        "edit"
      end
      url_for(action: target, only_path: true)
    else
      request.path
    end
    "#{path}?#{request.query_parameters.merge("locale" => locale).to_query}"
  end

  BADGE_TONES = {
    "new" => "attention",
    "confirmed" => "info",
    "preparing" => "warning",
    "awaiting_pickup" => "attention",
    "picked_up" => "info",
    "in_transit" => "info",
    "out_for_delivery" => "info",
    "unreachable" => "warning",
    "postponed" => "warning",
    "address_issue" => "warning",
    "shipped" => "info",
    "delivered" => "success",
    "cancelled" => "neutral",
    "returned" => "critical",
    "active" => "success",
    "draft" => "info",
    "archived" => "neutral"
  }.freeze

  # Admin icon names (menu entries and buttons) to Lucide icons.
  ICONS = {
    home: "house", orders: "clipboard-list", carts: "shopping-cart", products: "package",
    collections: "layout-grid", discounts: "badge-percent", customers: "user", staff: "users",
    settings: "settings", store: "store", search: "search", back: "chevron-left", external: "plug",
    logout: "log-out", menu: "menu", inventory: "warehouse", purchases: "shopping-basket", expenses: "wallet",
    delivery: "truck", call_center: "phone-call", advertising: "megaphone", whatsapp: "message-circle",
    analytics: "chart-line", accounting: "calculator", workflows: "workflow", billing: "credit-card",
    app: "smartphone", ai_chat: "bot", help: "circle-question-mark", image: "image"
  }.freeze

  # Lucide (ISC) icons vendored in vendor/icons/lucide; trusted static files, so the markup is html_safe.
  LUCIDE_ICONS = Dir[Rails.root.join("vendor/icons/lucide/*.svg")].to_h do |file|
    [ File.basename(file, ".svg"), File.read(file)[%r{<svg[^>]*>(.*)</svg>}m, 1].to_s.strip.html_safe ]
  end.freeze

  def lucide_icon(name, size: 20, **options)
    tag.svg(LUCIDE_ICONS.fetch(name.to_s), width: size, height: size, viewBox: "0 0 24 24", fill: "none",
            stroke: "currentColor", "stroke-width": 2, "stroke-linecap": "round", "stroke-linejoin": "round",
            "aria-hidden": true, class: [ "shrink-0", options[:class] ].compact.join(" "))
  end

  def admin_icon(name, size: 20)
    lucide_icon(ICONS.fetch(name), size: size)
  end

  def workspace_member_role(user)
    return t("platform_admin.impersonate.roles.agent") if user.confirmation_agent?
    return t("platform_admin.impersonate.roles.admin") if user.admin?

    t("platform_admin.impersonate.roles.supervisor")
  end

  def impersonatable_staff(store)
    store.users.select(&:impersonatable_by_super_admin?).sort_by { |user| [ user.name.to_s.downcase, user.email ] }
  end

  def admin_badge(status, label: nil, tone: nil)
    tone ||= BADGE_TONES.fetch(status.to_s, "neutral")
    label ||= Order::STATUS_LABELS[status.to_s] || status.to_s.humanize
    tag.span(class: "admin-badge admin-badge--#{tone}") do
      tag.span(class: "admin-badge__dot") + label
    end
  end

  # Badge tones for every official Sendit delivery status (GET /all-status-deliveries)
  SENDIT_TONES = {
    "PENDING" => "neutral",
    "TO_PREPARE" => "attention",
    "NEW_DESTINATION" => "warning",
    "TO_PICKUP" => "attention",
    "PICKEDUP" => "info",
    "WAREHOUSE" => "info",
    "TRANSIT" => "info",
    "DISTRIBUTED" => "info",
    "UNREACHABLE" => "warning",
    "POSTPONED" => "warning",
    "DELIVERING" => "info",
    "DELIVERED" => "success",
    "CANCELED" => "neutral",
    "REJECTED" => "critical"
  }.freeze

  def sendit_badge(order)
    return admin_badge(:error, label: "Sync error", tone: "critical") if order.sendit_error.present? && order.sendit_code.blank?
    return if order.sendit_status.blank?

    status = Sendit::Sync.normalize_status(order.sendit_status)
    admin_badge(status, label: order.sendit_label, tone: SENDIT_TONES.fetch(status, "neutral"))
  end

  OZON_TONES = {
    "NEW_PARCEL" => "neutral",
    "WAITING_PICKUP" => "warning",
    "PRE_PICKED_UP" => "warning",
    "PICKED_UP" => "info",
    "SENT" => "info",
    "ONV" => "info",
    "RECEIVED" => "info",
    "DISTRIBUTION" => "info",
    "IN_PROGRESS" => "info",
    "DELIVERED" => "success",
    "RETURNED" => "critical",
    "REFUSE" => "critical",
    "DECLINED" => "critical",
    "CANCELED" => "neutral",
    "CANCELED_TEAM" => "neutral",
    "POSTPONED" => "warning",
    "UNREACHABLE" => "warning",
    "NOANSWER" => "warning",
    "OUT_OF_AREA" => "warning",
    "SANS_ADRE" => "warning",
    "EN" => "critical"
  }.freeze

  def ozon_badge(order)
    return admin_badge(:error, label: "Sync error", tone: "critical") if order.ozon_error.present? && order.ozon_code.blank?
    return if order.ozon_status.blank?

    status = Ozon::Sync.normalize_status(order.ozon_status)
    admin_badge(status, label: order.ozon_label, tone: OZON_TONES.fetch(status, "neutral"))
  end

  AMEEX_TONES = {
    "NEW_PARCEL" => "neutral",
    "WAITING_PICKUP" => "warning",
    "PICKED_UP" => "info",
    "IN_PROGRESS" => "info",
    "DELIVERED" => "success",
    "RETURNED" => "critical",
    "REFUSED" => "critical",
    "REFUSE" => "critical",
    "CANCELED" => "neutral",
    "POSTPONED" => "warning",
    "UNREACHABLE" => "warning",
    "NOANSWER" => "warning",
    "OUT_OF_AREA" => "warning"
  }.freeze

  def ameex_badge(order)
    return admin_badge(:error, label: "Sync error", tone: "critical") if order.ameex_error.present? && order.ameex_code.blank?
    return if order.ameex_status.blank?

    status = Ameex::Sync.normalize_status(order.ameex_status)
    admin_badge(status, label: order.ameex_label, tone: AMEEX_TONES.fetch(status, "neutral"))
  end

  def courier_badge(order)
    sendit_badge(order) || ozon_badge(order) || ameex_badge(order)
  end

  # Sendit districts grouped by city for a <select>, the order's likely city first
  def sendit_district_options(order)
    districts = Sendit::Districts.all(store: order.store)
    likely = Sendit::Districts.candidates(city: order.customer_city, districts: districts)
    groups = districts.group_by { |d| d[:ville] }.sort_by(&:first).map { |ville, ds| [ ville, ds.map { |d| [ d[:name], d[:id] ] } ] }
    groups.unshift([ "Suggested for “#{order.customer_city}”", likely.map { |d| [ d[:name], d[:id] ] } ]) if likely.any?
    grouped_options_for_select(groups, order.sendit_district_id)
  rescue Sendit::Client::Error
    ""
  end

  def ozon_city_options(order)
    cities = Ozon::Cities.all(store: order.store)
    likely = Ozon::Cities.candidates(city: order.customer_city, cities: cities)
    grouped = []
    grouped << [ "Suggested for “#{order.customer_city}”", likely.map { |c| [ c[:name], c[:id] ] } ] if likely.any?
    grouped << [ "All cities", cities.map { |c| [ c[:name], c[:id] ] } ]
    grouped_options_for_select(grouped, order.ozon_city_id)
  rescue Ozon::Client::Error
    ""
  end

  def ameex_city_options(order)
    cities = Ameex::Cities.all(store: order.store)
    likely = Ameex::Cities.candidates(city: order.customer_city, cities: cities)
    grouped = []
    grouped << [ "Suggested for “#{order.customer_city}”", likely.map { |c| [ c[:name], c[:id] ] } ] if likely.any?
    grouped << [ "All cities", cities.map { |c| [ c[:name], c[:id] ] } ]
    grouped_options_for_select(grouped, order.ameex_city_id)
  rescue Ameex::Client::Error
    ""
  end

  def admin_nav_link(label, path, icon:, active: false, **options)
    link_to path, class: "admin-nav-item #{"is-active" if active}", **options do
      admin_icon(icon) + tag.span(label)
    end
  end

  def admin_thumb(url)
    tag.span(class: "admin-thumb") do
      url.present? ? image_tag(MediaUrl.sized(url, width: 160), alt: "", loading: "lazy") : admin_icon(:image, size: 16)
    end
  end
end
