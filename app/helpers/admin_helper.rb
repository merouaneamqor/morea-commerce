module AdminHelper
  BADGE_TONES = {
    "new" => "attention",
    "confirmed" => "info",
    "preparing" => "warning",
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
    products: '<path d="M10 2.5 17 6v8l-7 3.5L3 14V6z"/><path d="m3 6 7 3.5L17 6M10 9.5v8"/>',
    collections: '<rect x="3" y="3" width="6" height="6" rx="1"/><rect x="11" y="3" width="6" height="6" rx="1"/><rect x="3" y="11" width="6" height="6" rx="1"/><rect x="11" y="11" width="6" height="6" rx="1"/>',
    customers: '<circle cx="10" cy="7" r="3.5"/><path d="M3.5 17.5a6.5 6.5 0 0 1 13 0"/>',
    settings: '<circle cx="10" cy="10" r="2.5"/><path d="M10 2.5v2M10 15.5v2M2.5 10h2M15.5 10h2M4.7 4.7l1.4 1.4M13.9 13.9l1.4 1.4M4.7 15.3l1.4-1.4M13.9 6.1l1.4-1.4"/>',
    store: '<path d="M3 8h14l-1-4H4z"/><path d="M4 8v9h12V8"/><path d="M8 17v-5h4v5"/>',
    search: '<circle cx="9" cy="9" r="5.5"/><path d="m13 13 4 4"/>',
    back: '<path d="M12 4 6 10l6 6"/>',
    external: '<path d="M11 3h6v6M17 3l-8 8"/><path d="M15 12v4a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V6a1 1 0 0 1 1-1h4"/>',
    logout: '<path d="M8 3H4a1 1 0 0 0-1 1v12a1 1 0 0 0 1 1h4M13 14l4-4-4-4M17 10H8"/>',
    menu: '<path d="M3 5h14M3 10h14M3 15h14"/>',
    image: '<rect x="3" y="3" width="14" height="14" rx="2"/><circle cx="7.5" cy="7.5" r="1.5"/><path d="m17 13-4-4-8 8"/>'
  }.freeze

  def admin_icon(name, size: 20)
    tag.svg(ICONS.fetch(name).html_safe, width: size, height: size, viewBox: "0 0 20 20", fill: "none",
            stroke: "currentColor", "stroke-width": 1.6, "stroke-linecap": "round", "stroke-linejoin": "round",
            "aria-hidden": true, class: "shrink-0")
  end

  def admin_badge(status, label: nil, tone: nil)
    tone ||= BADGE_TONES.fetch(status.to_s, "neutral")
    tag.span(class: "admin-badge admin-badge--#{tone}") do
      tag.span(class: "admin-badge__dot") + (label || status.to_s.humanize)
    end
  end

  SENDIT_TONES = {
    "PENDING" => "neutral", "TO_PREPARE" => "attention", "TO_PICKUP" => "attention", "NEW_DESTINATION" => "warning",
    "PICKEDUP" => "info", "WAREHOUSE" => "info", "TRANSIT" => "info", "DISTRIBUTED" => "info", "DELIVERING" => "info",
    "UNREACHABLE" => "warning", "POSTPONED" => "warning", "DELIVERED" => "success", "CANCELED" => "neutral", "REJECTED" => "critical"
  }.freeze

  def sendit_badge(order)
    return admin_badge(:error, label: "Sync error", tone: "critical") if order.sendit_error.present? && order.sendit_code.blank?
    return if order.sendit_status.blank?

    status = Sendit::Sync.normalize_status(order.sendit_status)
    admin_badge(status, label: order.sendit_label, tone: SENDIT_TONES.fetch(status, "neutral"))
  end

  # Sendit districts grouped by city for a <select>, the order's likely city first
  def sendit_district_options(order)
    districts = Sendit::Districts.all
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
      url.present? ? image_tag(url, alt: "", loading: "lazy") : admin_icon(:image, size: 16)
    end
  end
end
