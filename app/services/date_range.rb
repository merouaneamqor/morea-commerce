# frozen_string_literal: true

# A range of whole days chosen by the seller, shared by every page that has a date picker, so they all read and
# count dates the same way:
# - Days are Africa/Casablanca days, never the server's.
# - The end is inclusive: from 3 Nov to 3 Nov is the whole day, 00:00:00 to 23:59:59.999999.
# - No date after today: an end in the future is cut to today, and a range that starts in the future does not exist.
# - A start after the end is swapped with it.
# - The previous period is the same number of days just before (10 days: the 10 days before).
#
# Dates come from the URL (?from=2026-10-01&to=2026-10-31). The last choice is remembered per page in a cookie:
# a preset is remembered by name ("this month" stays this month next month), a custom range by its dates.
class DateRange
  ZONE = "Africa/Casablanca"
  MAX_DAYS = 1830 # five years; anything longer is ignored, not silently cut
  PRESETS = %w[today yesterday last_3 last_7 last_30 this_month last_month this_year q1 q2 q3 q4].freeze
  ISO = /\A\d{4}-\d{2}-\d{2}\z/

  attr_reader :from, :to, :today

  def initialize(from, to, today)
    @from = from
    @to = to
    @today = today
  end

  # Today in the store's timezone.
  def self.today(now = Time.current) = now.in_time_zone(ZONE).to_date

  # "2026-10-01" into a Date, strictly; anything else is nil.
  def self.parse_date(value)
    return unless value.is_a?(String) && value.match?(ISO)

    Date.iso8601(value)
  rescue Date::Error
    nil
  end

  # The safe way to make a range from two dates: swaps them when reversed, cuts the end to today, and refuses a
  # range that starts after today or is longer than MAX_DAYS.
  def self.build(from, to, today: self.today)
    return unless from.is_a?(Date) && to.is_a?(Date)

    from, to = to, from if from > to
    return if from > today

    to = today if to > today
    return if (to - from).to_i + 1 > MAX_DAYS

    new(from, to, today)
  end

  def self.preset(key, today: self.today)
    key = key.to_s
    from, to = case key
    when "today" then [ today, today ]
    when "yesterday" then [ today - 1, today - 1 ]
    when "last_3" then [ today - 2, today ]
    when "last_7" then [ today - 6, today ]
    when "last_30" then [ today - 29, today ]
    when "this_month" then [ today.beginning_of_month, today ]
    when "last_month" then [ (today.beginning_of_month - 1).beginning_of_month, today.beginning_of_month - 1 ]
    when "this_year" then [ today.beginning_of_year, today ]
    when /\Aq([1-4])\z/
      first = Date.new(today.year, (Regexp.last_match(1).to_i - 1) * 3 + 1, 1)
      [ first, (first >> 2).end_of_month ]
    end
    build(from, to, today: today) if from
  end

  # A whole month (cut to today for the current one).
  def self.for_month(date, today: self.today)
    build(date.beginning_of_month, date.end_of_month, today: today)
  end

  # nil unless both dates are valid; the caller then falls back to the remembered or default range.
  def self.from_params(params, today: self.today)
    build(parse_date(params[:from]), parse_date(params[:to]), today: today)
  end

  # The preset the URL says it was picked from, when it really is that range (it can be ambiguous: on the 3rd,
  # "this month" and "last 3 days" are the same days). A hint that does not match is ignored.
  def self.hinted_preset(key, range)
    key = key.to_s
    key if PRESETS.include?(key) && preset(key, today: range.today) == range
  end

  # Cookie value: "p:this_month" for a preset (stays relative), "c:2026-10-01:2026-10-15" for a custom range.
  def self.from_cookie(value, today: self.today)
    case value.to_s
    when /\Ap:([a-z0-9_]+)\z/
      key = Regexp.last_match(1)
      preset(key, today: today) if PRESETS.include?(key)
    when /\Ac:(\d{4}-\d{2}-\d{2}):(\d{4}-\d{2}-\d{2})\z/
      build(parse_date(Regexp.last_match(1)), parse_date(Regexp.last_match(2)), today: today)
    end
  end

  def to_cookie(preset_hint = nil)
    key = self.class.hinted_preset(preset_hint, self) || preset_key
    key ? "p:#{key}" : "c:#{from.iso8601}:#{to.iso8601}"
  end

  def days = (to - from).to_i + 1

  def dates = from..to

  def zone = Time.find_zone!(ZONE)

  # Start of the first day, and start of the day after the last one (exclusive), in absolute time.
  def start_time = zone.local(from.year, from.month, from.day)

  def end_time = zone.local(to.year, to.month, to.day) + 1.day

  # For queries: `where(created_at: range.time_range)`. Exclusive end, so 23:59:59.999999 on the last day is in.
  def time_range = start_time...end_time

  # The same number of days just before this range.
  def previous = self.class.new(from - days, from - 1, today)

  # The first preset that is exactly this range, or nil for a custom range.
  def preset_key = PRESETS.find { |key| self.class.preset(key, today: today) == self }

  def ==(other) = other.is_a?(DateRange) && from == other.from && to == other.to

  def to_param = { from: from.iso8601, to: to.iso8601 }
end
