# frozen_string_literal: true

# Text and settings of the shared date range picker (admin/shared/_date_range_picker).
module DateRangeHelper
  # "3 oct. -> 15 oct. 2026", "30 déc. 2025 -> 3 janv. 2026", one day: "3 nov. 2026".
  def date_range_text(range)
    short = ->(date, with_year) { "#{date.day} #{t("date_range.months_short")[date.month - 1]}#{" #{date.year}" if with_year}" }
    return short.(range.from, true) if range.from == range.to

    arrow = rtl? ? "←" : "→"
    same_year = range.from.year == range.to.year
    "#{short.(range.from, !same_year)} #{arrow} #{short.(range.to, true)}"
  end

  # What the button shows: the preset's name ("Ce mois"), or the dates of a custom range.
  def date_range_label(range, preset)
    key = preset.presence || range.preset_key
    key ? t("date_range.presets.#{key}") : date_range_text(range)
  end

  # The presets that exist today, as [key, label, range] (a quarter that has not started is left out).
  def date_range_presets(today)
    DateRange::PRESETS.filter_map do |key|
      range = DateRange.preset(key, today: today)
      [ key, t("date_range.presets.#{key}"), range ] if range
    end
  end

  # Link of a preset (it works without JavaScript).
  def date_range_link(url, range, key, extra)
    "#{url}?#{extra.merge(range.to_param).merge(preset: key).to_query}"
  end

  # Everything the Stimulus controller needs, as JSON for a data attribute.
  def date_range_config(range:, url:, extra:)
    {
      today: range.today.iso8601, from: range.from.iso8601, to: range.to.iso8601, url: url, extra: extra.transform_keys(&:to_s).transform_values(&:to_s), rtl: rtl?,
      presets: date_range_presets(range.today).map { |key, _label, found| { key: key, from: found.from.iso8601, to: found.to.iso8601 } },
      months: t("date_range.months"), monthsShort: t("date_range.months_short"), weekdays: t("date_range.weekdays"),
      labels: { start: t("date_range.start"), end: t("date_range.end"), apply: t("date_range.apply"), cancel: t("date_range.cancel"),
                pickEnd: t("date_range.pick_end"), previous: t("date_range.previous_month"), next: t("date_range.next_month"),
                daysOne: t("date_range.days.one", count: 1), daysOther: t("date_range.days.other", count: "%{count}") }
    }
  end
end
