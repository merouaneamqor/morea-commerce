# frozen_string_literal: true

# Reads the date range of a page from the URL (?from=&to=), else from the last choice made on that page (cookie),
# else from the page's default preset. A choice made through the URL is remembered for next time.
module DateRangeSelection
  extend ActiveSupport::Concern

  COOKIE_PREFIX = "dr_"

  private

  # scope: a short name of the page ("dashboard", "accounting"...), so each page remembers its own range.
  # Also sets @date_range_preset: the preset the range is (or was picked as), nil for a custom range, so the picker
  # button can say "Ce mois" rather than the dates.
  def selected_date_range(scope:, default: "last_30", from: nil, to: nil)
    today = DateRange.today
    explicit = DateRange.from_params({ from: from || params[:from], to: to || params[:to] }, today: today)
    if explicit
      @date_range_preset = DateRange.hinted_preset(params[:preset], explicit) || explicit.preset_key
      cookies[cookie_name(scope)] = { value: explicit.to_cookie(@date_range_preset), expires: 1.year.from_now, path: "/", httponly: true,
                                      same_site: :lax, secure: !Rails.env.local? }
      return explicit
    end

    raw = cookies[cookie_name(scope)]
    remembered = DateRange.from_cookie(raw, today: today)
    if remembered
      @date_range_preset = raw.to_s[/\Ap:([a-z0-9_]+)\z/, 1] || remembered.preset_key
      return remembered
    end

    fallback = DateRange.preset(default, today: today)
    @date_range_preset = default
    fallback
  end

  def cookie_name(scope) = "#{COOKIE_PREFIX}#{scope.to_s.gsub(/[^a-z_]/, "")}"
end
