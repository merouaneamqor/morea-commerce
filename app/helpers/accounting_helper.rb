# frozen_string_literal: true

# Printing of the Comptabilité figures. This is the only place that rounds: AccountingStats hands over whole
# centimes and exact fractions, and they are turned into text here.
module AccountingHelper
  DASH = 0x2014.chr(Encoding::UTF_8) # an em dash
  MINUS = 0x2212.chr(Encoding::UTF_8) # a real minus sign
  SPACE = 0x00A0.chr(Encoding::UTF_8) # non-breaking space
  LTR_START = 0x2066.chr(Encoding::UTF_8) # keeps a number left-to-right inside Arabic text
  LTR_END = 0x2069.chr(Encoding::UTF_8)

  # Whole centimes as "186 450" (or "186 450,25" when there are centimes).
  def acc_amount(cents)
    return DASH if cents.nil?

    cents = cents.round if cents.is_a?(Rational) # half away from zero, once, at display time
    sign = cents.negative? ? MINUS : ""
    whole = cents.abs / 100
    rest = cents.abs % 100
    digits = whole.to_s.reverse.scan(/\d{1,3}/).join(SPACE).reverse
    text = rest.zero? ? digits : "#{digits},#{format("%02d", rest)}"
    "#{LTR_START}#{sign}#{text}#{LTR_END}"
  end

  # Whole centimes with the two decimals always shown ("4 738,00"), as in a statement.
  def acc_exact(cents)
    cents = cents.round if cents.is_a?(Rational)
    sign = cents.negative? ? MINUS : ""
    digits = (cents.abs / 100).to_s.reverse.scan(/\d{1,3}/).join(SPACE).reverse
    "#{LTR_START}#{sign}#{digits},#{format("%02d", cents.abs % 100)}#{LTR_END}"
  end

  # A cost in brackets, as expenses are written in a statement: "(2 151,33 MAD)".
  def acc_expense(cents, currency)
    "(#{acc_exact(cents)}#{SPACE}#{currency})"
  end

  # A ratio (0.325 is 32.5 %) as "32,5", one decimal, half up.
  def acc_percent(ratio)
    return DASH if ratio.nil?

    tenths = (Rational(ratio) * 1000).round
    "#{LTR_START}#{tenths.negative? ? MINUS : ""}#{tenths.abs / 10},#{tenths.abs % 10}#{LTR_END}"
  end

  # A share given in tenths of a point (260 is 26.0), as "26,0".
  def acc_tenths(tenths)
    "#{LTR_START}#{tenths / 10},#{tenths % 10}#{LTR_END}"
  end

  # [text, tone] of a "change versus the previous period": tone is :up, :down or :flat.
  def acc_change(change)
    return [ DASH, :flat ] if change.nil?
    return [ t("accounting.new"), :flat ] if change == :new

    whole = Rational(change).round
    arrow = whole.positive? ? "↗ " : (whole.negative? ? "↘ " : "")
    [ "#{arrow}#{whole.abs} %", acc_tone(whole) ]
  end

  def acc_points_change(points)
    return [ DASH, :flat ] if points.nil?

    tenths = (Rational(points) * 10).round
    arrow = tenths.positive? ? "↗ " : (tenths.negative? ? "↘ " : "")
    [ "#{arrow}#{tenths.abs / 10},#{tenths.abs % 10} #{t("accounting.points")}", acc_tone(tenths) ]
  end

  # Pill colours: for a cost, going up is bad.
  def acc_pill_class(tone, good_when)
    return "bg-[#f1eee9] text-[#6f6967]" if tone == :flat

    ((tone == :up) == (good_when == :up)) ? "bg-[#e3f3e8] text-[#2f7a4a]" : "bg-[#fbe7ea] text-[#b4344e]"
  end

  def acc_spark_color(good_when, series)
    ((series.last.to_f >= series.first.to_f) == (good_when == :up)) ? "#2f7a4a" : "#b4344e"
  end

  # Small curve of a card. Floats are fine here: it is a drawing, not a figure.
  def acc_sparkline(values, color:, width: 96, height: 30)
    numbers = values.map { |value| value.nil? ? 0.0 : value.to_f }
    low, high = numbers.minmax
    span = high - low
    step = numbers.length > 1 ? width.to_f / (numbers.length - 1) : 0
    points = numbers.each_with_index.map do |number, index|
      y = span.zero? ? height / 2.0 : height - 3 - ((number - low) / span) * (height - 6)
      "#{(index * step).round(1)},#{y.round(1)}"
    end
    last = points.last.split(",")
    tag.svg(viewBox: "0 0 #{width} #{height}", width: width, height: height, class: "shrink-0 overflow-visible", "aria-hidden": "true", dir: "ltr") do
      safe_join([ tag.polyline(points: points.join(" "), fill: "none", stroke: color, "stroke-width": 1.8, "stroke-linecap": "round", "stroke-linejoin": "round"),
                  tag.circle(cx: last[0], cy: last[1], r: 2.6, fill: "#fff", stroke: color, "stroke-width": 1.6) ])
    end
  end

  private

  def acc_tone(number)
    number.positive? ? :up : (number.negative? ? :down : :flat)
  end
end
