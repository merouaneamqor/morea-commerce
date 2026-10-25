module AdminHelper
  def admin_language_switch_path(locale)
    path = if !request.get? && action_name.in?(%w[create update])
      url_for(action: action_name == "create" ? "new" : "edit", only_path: true)
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

  ICONS = {
    home: '<path d="M3 10.5 10 4l7 6.5V17a1 1 0 0 1-1 1h-3.5v-5h-5v5H4a1 1 0 0 1-1-1z"/>',
    orders: '<path d="M4 3h12l-1 14H5z"/><path d="M7.5 7a2.5 2.5 0 0 0 5 0"/>',
    carts: '<path d="M3 5h2l1.2 9h9.6L17 7H6"/><circle cx="8" cy="16.5" r="1.2"/><circle cx="14" cy="16.5" r="1.2"/>',
    products: '<path d="M10 2.5 17 6v8l-7 3.5L3 14V6z"/><path d="m3 6 7 3.5L17 6M10 9.5v8"/>',
    collections: '<rect x="3" y="3" width="6" height="6" rx="1"/><rect x="11" y="3" width="6" height="6" rx="1"/><rect x="3" y="11" width="6" height="6" rx="1"/><rect x="11" y="11" width="6" height="6" rx="1"/>',
    discounts: '<path d="M3.5 10.5 10.5 3.5l6 6-7 7z"/><circle cx="7.5" cy="7.5" r="1.2"/>',
    customers: '<circle cx="10" cy="7" r="3.5"/><path d="M3.5 17.5a6.5 6.5 0 0 1 13 0"/>',
    staff: '<circle cx="7" cy="7" r="2.5"/><circle cx="13" cy="7" r="2.5"/><path d="M2.5 16.5a4.5 4.5 0 0 1 9 0M8.5 16.5a4.5 4.5 0 0 1 9 0"/>',
    settings: '<circle cx="10" cy="10" r="2.5"/><path d="M10 2.5v2M10 15.5v2M2.5 10h2M15.5 10h2M4.7 4.7l1.4 1.4M13.9 13.9l1.4 1.4M4.7 15.3l1.4-1.4M13.9 6.1l1.4-1.4"/>',
    store: '<path d="M3 8h14l-1-4H4z"/><path d="M4 8v9h12V8"/><path d="M8 17v-5h4v5"/>',
    search: '<circle cx="9" cy="9" r="5.5"/><path d="m13 13 4 4"/>',
    back: '<path d="M12 4 6 10l6 6"/>',
    external: '<path d="M11 3h6v6M17 3l-8 8"/><path d="M15 12v4a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V6a1 1 0 0 1 1-1h4"/>',
    logout: '<path d="M8 3H4a1 1 0 0 0-1 1v12a1 1 0 0 0 1 1h4M13 14l4-4-4-4M17 10H8"/>',
    menu: '<path d="M3 5h14M3 10h14M3 15h14"/>',
    inventory: '<path d="M3 7h14v10H3z"/><path d="M3 7l2-4h10l2 4M8 11h4"/>',
    purchases: '<path d="M3 4h2l1.5 8h8L17 6H6"/><path d="M10 14v3M8.5 15.5h3"/>',
    expenses: '<rect x="2.5" y="5" width="15" height="10" rx="1.5"/><circle cx="10" cy="10" r="2.2"/>',
    delivery: '<path d="M2.5 5h9v8h-9zM11.5 8h3l2 2.5V13h-5z"/><circle cx="6" cy="14.5" r="1.3"/><circle cx="14" cy="14.5" r="1.3"/>',
    call_center: '<path d="M5 3h3l1.2 3.2-1.8 1.2a9 9 0 0 0 4.2 4.2l1.2-1.8L16.8 11v3a2 2 0 0 1-2 2A12 12 0 0 1 3 4.8a2 2 0 0 1 2-1.8z"/>',
    advertising: '<path d="M3 8v4h3l7 4V4L6 8z"/><path d="M16 8.5a2.5 2.5 0 0 1 0 3"/>',
    whatsapp: '<path d="M3 17l1.2-3.6A7 7 0 1 1 7 16z"/>',
    analytics: '<path d="M3 17V3M3 17h14"/><path d="M6.5 13l3-4 3 2 4-6"/>',
    accounting: '<rect x="4" y="3" width="12" height="14" rx="1.5"/><path d="M7 7h6M7 11h1M10 11h1M13 11h0M7 14h1M10 14h1"/>',
    workflows: '<circle cx="5" cy="5" r="2"/><circle cx="15" cy="10" r="2"/><circle cx="5" cy="15" r="2"/><path d="M7 5h3a3 3 0 0 1 3 3v0M7 15h3a3 3 0 0 0 3-3v0"/>',
    billing: '<rect x="2.5" y="4.5" width="15" height="11" rx="1.5"/><path d="M2.5 8.5h15M5.5 12.5h3"/>',
    app: '<rect x="6" y="2.5" width="8" height="15" rx="1.5"/><path d="M9 15h2"/>',
    ai_chat: '<path d="M3 4h14v9H9l-4 3v-3H3z"/><path d="M7 8h6"/>',
    help: '<circle cx="10" cy="10" r="7"/><path d="M8 8a2 2 0 1 1 3 1.7c-.7.4-1 .8-1 1.6M10 14h.01"/>',
    image: '<rect x="3" y="3" width="14" height="14" rx="2"/><circle cx="7.5" cy="7.5" r="1.5"/><path d="m17 13-4-4-8 8"/>'
  }.freeze

  def admin_icon(name, size: 20)
    tag.svg(ICONS.fetch(name).html_safe, width: size, height: size, viewBox: "0 0 20 20", fill: "none",
            stroke: "currentColor", "stroke-width": 1.6, "stroke-linecap": "round", "stroke-linejoin": "round",
            "aria-hidden": true, class: "shrink-0")
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
