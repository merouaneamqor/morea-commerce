module ConfirmationsHelper
  # An order waiting longer than this is marked so the agent confirms it before it goes stale.
  CONFIRM_SOON_AFTER = 30.minutes

  def confirmation_waiting_since(order, confirmation)
    if confirmation&.disposition == "callback" && confirmation.callback_at.present?
      confirmation.callback_at
    else
      order.created_at
    end
  end

  def confirmation_waiting_long?(since)
    since <= CONFIRM_SOON_AFTER.ago
  end

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
    rate ? number_to_percentage(rate * 100, precision: 0) : I18n.t("admin_ui.blank")
  end

  def confirmations_per_hour_label(value)
    value ? number_with_precision(value, precision: 1) : I18n.t("admin_ui.blank")
  end
end
