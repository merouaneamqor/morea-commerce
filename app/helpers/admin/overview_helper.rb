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

  def overview_line_chart(days, currency)
    {
      type: "line",
      data: {
        labels: days.map { |day| l(day[:date], format: t("overview.date_format")) },
        datasets: [
          { label: t("overview.order_value"), data: days.map { |day| day[:values].fetch(currency, 0).fdiv(100) } },
          { label: t("overview.delivered_sales"), data: days.map { |day| day[:delivered_values].fetch(currency, 0).fdiv(100) }, borderDash: [ 6, 4 ] }
        ]
      }
    }
  end

  def overview_status_chart(counts)
    colors = {
      "new" => "#c4a0a3",
      "confirmed" => "#9a6f72",
      "preparing" => "#4a4340",
      "shipped" => "#1a1716",
      "delivered" => "#2f6f52",
      "address_issue" => "#b7791f",
      "unreachable" => "#b7791f",
      "postponed" => "#8a827c",
      "cancelled" => "#9b3a46",
      "returned" => "#b7791f"
    }

    {
      type: "doughnut",
      data: {
        labels: counts.keys.map { |status| t("dashboard.order_statuses.#{status}") },
        datasets: [ { data: counts.values, statuses: counts.keys, backgroundColor: counts.keys.map { |status| colors.fetch(status, "#8a827c") } } ]
      }
    }
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
end
