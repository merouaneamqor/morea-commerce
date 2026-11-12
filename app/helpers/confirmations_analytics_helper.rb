# Drawing helpers of the call-center Analyses page: small inline SVG charts and the text formats. The figures themselves come from
# Confirmations::Analytics; nothing here computes a business number, it only turns the numbers into marks.
module ConfirmationsAnalyticsHelper
  WEEKDAYS = %w[lun. mar. mer. jeu. ven. sam. dim.].freeze

  def analytics_percent(value)
    value.nil? ? "—" : "#{number_with_precision(value, precision: 1, strip_insignificant_zeros: false)} %".sub(".", ",")
  end

  def analytics_integer(value) = number_with_delimiter(value.to_i, delimiter: " ")

  # 8 h 29 min, 45 min, 52 j 2 h
  def analytics_duration(seconds)
    return "—" if seconds.nil?

    minutes = (seconds / 60.0).round
    return "#{minutes} min" if minutes < 60
    return "#{minutes / 60} h #{format("%02d", minutes % 60)} min" if minutes < 24 * 60

    days, rest = minutes.divmod(24 * 60)
    "#{days} j #{rest / 60} h"
  end

  # Two lines of a small chart in a 100 x 30 box; values may be nil (the line is simply not drawn there). The last
  # `dashed_from..` points are provisional and drawn dashed.
  def analytics_sparkline(values, dashed_from: nil, color: "#1c1c1e", size: "h-7 w-full")
    points = analytics_points(values, max: values.compact.max.to_f, height: 28, top: 1)
    solid, dashed = analytics_split(points, dashed_from)
    tag.svg(viewBox: "0 0 100 30", preserveAspectRatio: "none", class: size, role: "img", "aria-hidden": "true") do
      safe_join([
        (tag.polyline(points: analytics_join(solid), fill: "none", stroke: color, "stroke-width": 1.6, "vector-effect": "non-scaling-stroke", "stroke-linejoin": "round") if solid.size > 1),
        (tag.polyline(points: analytics_join(dashed), fill: "none", stroke: "#9a9da6", "stroke-width": 1.4, "stroke-dasharray": "3 3", "vector-effect": "non-scaling-stroke") if dashed.size > 1)
      ].compact)
    end
  end

  # A line chart with grid lines. series: [{ values:, color:, area: false }]; max: the top of the scale; shade_from: index
  # from which the background is grey (provisional days).
  def analytics_line_chart(series, max:, shade_from: nil, count: nil, height: "h-32")
    count ||= series.first[:values].size
    max = max.to_f.positive? ? max.to_f : 1.0
    grid = [ 0, 0.25, 0.5, 0.75, 1 ].map { |share| tag.line(x1: 0, x2: 100, y1: (39 - share * 38).round(2), y2: (39 - share * 38).round(2), stroke: "#e8e8ed", "stroke-width": 1, "vector-effect": "non-scaling-stroke") }
    shade = shade_from && count > 1 ? tag.rect(x: (shade_from * 100.0 / (count - 1)).round(2), y: 0, width: (100 - shade_from * 100.0 / (count - 1)).round(2), height: 40, fill: "#ececf0", opacity: 0.7) : nil
    lines = series.flat_map do |line|
      points = analytics_points(line[:values], max: max, height: 38, top: 1, count: count)
      path = analytics_join(points)
      area = line[:area] && points.size > 1 ? tag.polygon(points: "#{points.first[0]},39 #{path} #{points.last[0]},39", fill: line[:color], opacity: 0.1) : nil
      [ area, (tag.polyline(points: path, fill: "none", stroke: line[:color], "stroke-width": 2, "vector-effect": "non-scaling-stroke", "stroke-linejoin": "round", "stroke-linecap": "round") if points.size > 1) ]
    end
    tag.svg(viewBox: "0 0 100 40", preserveAspectRatio: "none", class: "#{height} w-full", role: "img") { safe_join([ shade, *grid, *lines ].compact) }
  end

  # A ring like the dashboard's distribution: segments [{ count:, color: }], each drawn through the .donut-seg animation.
  def analytics_donut(segments, size: "size-32")
    total = segments.sum { |segment| segment[:count] }.to_f
    offset = 0.0
    shown = segments.select { |segment| segment[:count].positive? }
    rings = shown.map do |segment|
      share = segment[:count] / total * 100
      length = shown.size > 1 ? [ share - 0.6, 0.2 ].max : share
      circle = tag.circle(class: "donut-seg", cx: 21, cy: 21, r: 15.9155, fill: "none", stroke: segment[:color], "stroke-width": 5.5, style: "--len: #{length.round(3)}; stroke-dashoffset: -#{offset.round(3)}", "data-count": segment[:count])
      offset += share
      circle
    end
    tag.svg(viewBox: "0 0 42 42", class: "#{size} -rotate-90", role: "img") do
      safe_join([ tag.circle(cx: 21, cy: 21, r: 15.9155, fill: "none", stroke: "#efeff3", "stroke-width": 5.5), *rings ])
    end
  end

  # Colour of a heat-map cell: the sky blue of "reached by phone", darker when more calls were answered; light grey when there was no call.
  def analytics_heat_style(cell)
    return "background: #f3f4f7" if cell[:rate].nil?

    "background: rgba(90, 180, 239, #{(0.14 + 0.86 * cell[:rate] / 100.0).round(2)})"
  end

  FULL_WEEKDAYS = %w[lundi mardi mercredi jeudi vendredi samedi dimanche].freeze

  def analytics_slot_label(slot) = "#{FULL_WEEKDAYS[slot[:wday]]} à #{slot[:hour]}:00"

  def analytics_weekday(index) = WEEKDAYS[index]

  private

  def analytics_points(values, max:, height:, top:, count: nil)
    count ||= values.size
    max = 1.0 unless max.positive?
    values.each_with_index.filter_map do |value, index|
      next if value.nil?

      x = count > 1 ? index * 100.0 / (count - 1) : 50.0
      [ x.round(2), (top + height - value / max * height).round(2), index ]
    end
  end

  # Solid up to the first provisional point, dashed from the point before it (so the two parts touch).
  def analytics_split(points, dashed_from)
    return [ points, [] ] if dashed_from.nil?

    [ points.select { |point| point[2] < dashed_from }, points.select { |point| point[2] >= dashed_from - 1 } ]
  end

  def analytics_join(points) = points.map { |x, y, _| "#{x},#{y}" }.join(" ")
end
