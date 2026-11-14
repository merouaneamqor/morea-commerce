# Icons and partner logos for the apex landing page (same artwork as the seallo landing page).
module PlatformHomeHelper
  PLATFORM_ICONS = {
    bag: '<path d="M6 7h12l-1 13H7L6 7z"/><path d="M9 7a3 3 0 0 1 6 0"/>',
    confirm: '<path d="M22 16.9v3a2 2 0 0 1-2.2 2 19.8 19.8 0 0 1-8.6-3.1 19.5 19.5 0 0 1-6-6A19.8 19.8 0 0 1 2.1 4.2 2 2 0 0 1 4.1 2h3a2 2 0 0 1 2 1.7c.1.9.4 1.8.7 2.7a2 2 0 0 1-.5 2.1L8 9.8a16 16 0 0 0 6 6l1.3-1.3a2 2 0 0 1 2.1-.4c.9.3 1.8.6 2.7.7a2 2 0 0 1 1.7 2z"/><path d="m14.5 6.5 2 2 4-4"/>',
    delivery: '<path d="M14 18V6a2 2 0 0 0-2-2H4a2 2 0 0 0-2 2v11a1 1 0 0 0 1 1h2"/><path d="M15 18H9"/><path d="M19 18h2a1 1 0 0 0 1-1v-3.6a1 1 0 0 0-.2-.6l-3.5-4.4A1 1 0 0 0 17.5 8H14"/><circle cx="17" cy="18" r="2"/><circle cx="7" cy="18" r="2"/>',
    ads: '<path d="M3 11v3a1 1 0 0 0 1 1h2l5 4V6L6 10H4a1 1 0 0 0-1 1z"/><path d="M15.5 8.5a5 5 0 0 1 0 7"/><path d="M18.5 5.5a9 9 0 0 1 0 13"/>',
    profit: '<path d="M3 3v18h18"/><path d="m7 15 4-4 3 3 6-6"/><path d="M15 8h5v5"/>',
    team: '<circle cx="9" cy="8" r="3.5"/><path d="M2.5 20a6.5 6.5 0 0 1 13 0"/><path d="M16 4.5a3.5 3.5 0 0 1 0 7"/><path d="M18 14a6.5 6.5 0 0 1 3.5 6"/>',
    flow_ok: '<circle cx="12" cy="12" r="9"/><path d="m8 12 3 3 5-6"/>',
    flow_truck: '<path d="M3 6h11v10H3z"/><path d="M14 9h4l3 3v4h-7"/><circle cx="7" cy="17.5" r="1.8"/><circle cx="17" cy="17.5" r="1.8"/>',
    pin: '<path d="M12 21s-6-5.3-6-10a6 6 0 0 1 12 0c0 4.7-6 10-6 10z"/><circle cx="12" cy="11" r="2.2"/>',
    step_order: '<path d="M6 2 3 6v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6l-3-4Z"/><path d="M3 6h18"/><path d="M16 10a4 4 0 0 1-8 0"/>',
    step_confirm: '<path d="M21.8 10A10 10 0 1 1 17 3.3"/><path d="m9 11 3 3L22 4"/>',
    step_ship: '<path d="m16 16 2 2 4-4"/><path d="M21 10V8a2 2 0 0 0-1-1.7l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.7l7 4a2 2 0 0 0 2 0l2-1.1"/><path d="m7.5 4.3 9 5.2"/><path d="M3.3 7 12 12l8.7-5"/><path d="M12 22V12"/>',
    step_track: '<path d="M20 10c0 5-5.5 10.2-7.4 11.8a1 1 0 0 1-1.2 0C9.5 20.2 4 15 4 10a8 8 0 0 1 16 0"/><circle cx="12" cy="10" r="3"/>',
    step_profit: '<path d="M16 7h6v6"/><path d="m22 7-8.5 8.5-5-5L2 17"/>'
  }.freeze

  PLATFORM_FEATURE_ICONS = %i[bag confirm delivery ads profit team].freeze
  PLATFORM_FLOW_ICONS = %i[step_order step_confirm step_ship step_track step_profit].freeze
  PLATFORM_FLOW_TONES = %w[yellow gray gray gray green].freeze
  PLATFORM_WHY_ICONS = %i[bag confirm delivery pin ads profit].freeze

  PLATFORM_PARTNER_GROUPS = [
    [ :stores, [ [ "Shopify", "shopify", 24 ], [ "YouCan", "youcan", 24 ], [ "WooCommerce", "woocommerce", 24 ] ] ],
    [ :delivery, [ [ "Sendit", "sendit", 24 ], [ "Ozon Express", "ozon", 24 ], [ "Cathedis", "cathedis", 15 ], [ "Ameex", "ameex", 13 ] ] ],
    [ :ads, [ [ "Meta Ads", "meta", 15 ], [ "TikTok Ads", "tiktok", 24 ] ] ]
  ].freeze

  def platform_icon(name)
    tag.svg(PLATFORM_ICONS.fetch(name).html_safe, viewBox: "0 0 24 24", "aria-hidden": "true", focusable: "false")
  end
end
