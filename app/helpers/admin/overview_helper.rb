module Admin::OverviewHelper
  def overview_money_values(values)
    return "—" if values.empty?

    safe_join(values.sort.map { |currency, cents| dashboard_money(cents, currency) }, tag.br)
  end

  def overview_change(current, previous)
    return t("overview.no_comparison") if previous.to_f.zero?

    change = (current - previous) * 100.0 / previous
    t("overview.change", value: "#{change.positive? ? '+' : ''}#{number_with_precision(change, precision: 1)}%")
  end

  def overview_chart_points(days, currency, key, maximum)
    days.each_with_index.map do |day, index|
      x = 24 + index * 552.0 / [ days.length - 1, 1 ].max
      y = 174 - day.fetch(key).fetch(currency, 0) * 150.0 / maximum
      "#{x.round(2)},#{y.round(2)}"
    end.join(" ")
  end
  def overview_rate_change(current, previous)
    difference = current - previous
    t("overview.rate_change", value: "#{difference.positive? ? '+' : ''}#{number_with_precision(difference, precision: 1)}")
  end

  def overview_delivered_change(overview)
    currencies = (overview.delivered_values.keys + overview.previous_delivered_values.keys).uniq.sort
    safe_join(currencies.map do |currency|
      "#{currency}: #{overview_change(overview.delivered_values.fetch(currency, 0), overview.previous_delivered_values.fetch(currency, 0))}"
    end, tag.br)
  end

  def overview_status_segments(counts)
    total = counts.values.sum
    offset = 0
    counts.each_with_index.map do |(status, count), index|
      length = total.zero? ? 0 : count * 100.0 / total
      segment = { status: status, length: length, offset: offset, opacity: [ 1.0 - index * 0.07, 0.2 ].max }
      offset += length
      segment
    end
  end
end
