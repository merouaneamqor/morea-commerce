module ConfirmationsHelper
  # h:mm for totals; hh:mm:ss for the live clock.
  def shift_hours(seconds)
    seconds = seconds.to_i
    format("%d:%02d", seconds / 3600, seconds % 3600 / 60)
  end

  def shift_clock(seconds)
    seconds = seconds.to_i
    format("%02d:%02d:%02d", seconds / 3600, seconds % 3600 / 60, seconds % 60)
  end

  def confirmation_rate_label(rate)
    rate ? number_to_percentage(rate * 100, precision: 0) : "—"
  end

  def confirmations_per_hour_label(value)
    value ? number_with_precision(value, precision: 1) : "—"
  end
end
