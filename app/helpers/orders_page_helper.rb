# frozen_string_literal: true

# Labels and colours of the two states printed on every row of the Orders page, derived with the same rules as the
# figures at the top (Orders::Overview), so a row and the card that counts it always agree.
module OrdersPageHelper
  CONFIRMATION_BADGES = {
    "pending" => "bg-[#fff3d6] text-[#8a5a12]", "no_answer" => "bg-[#fff3d6] text-[#8a5a12]", "planned" => "bg-[#e1edfb] text-[#2b5f9e]",
    "confirmed" => "bg-[#e3f3e8] text-[#2f7a4a]", "cancelled" => "bg-[#fbe7ea] text-[#b4344e]", "wrong" => "bg-[#ececf0] text-[#3a3a3c]",
    "blocked" => "bg-[#1c1c1e] text-white"
  }.freeze
  SHIPPING_BADGES = {
    "to_ship" => "bg-[#ececf0] text-[#3a3a3c]", "in_transit" => "bg-[#e1edfb] text-[#2b5f9e]", "scheduled" => "bg-[#eee8fb] text-[#5b3fb0]",
    "delivered" => "bg-[#e3f3e8] text-[#2f7a4a]", "failed" => "bg-[#fdf0d9] text-[#8a5a12]", "returned" => "bg-[#fbe7ea] text-[#b4344e]",
    "none" => "text-[#8e8e93]"
  }.freeze

  # pending, no_answer, planned, confirmed, cancelled, wrong or blocked. No answer counts as pending on the cards.
  def order_confirmation_state(order)
    return "cancelled" if order.status == "cancelled"
    return "confirmed" unless order.status == "new"

    case order.order_confirmation&.disposition
    when "callback" then "planned"
    when "wrong_number" then "wrong"
    when "blocked" then "blocked"
    when "no_answer" then "no_answer"
    else "pending"
    end
  end

  # Only a confirmed order has a shipping stage; the others print a dash.
  def order_shipping_state(order)
    Orders::Overview::SHIPPING_GROUPS.find { |_key, statuses| statuses.include?(order.status) }&.first || "none"
  end

  def order_state_badge(group, key)
    classes = (group == :confirmation ? CONFIRMATION_BADGES : SHIPPING_BADGES).fetch(key, "")
    tag.span(t("orders_page.states.#{key}"), class: "inline-flex rounded-full px-2 py-0.5 text-[11px] font-semibold whitespace-nowrap #{classes}")
  end

  # The edit link is shown when the order can still change; the edit page checks again.
  def order_editable_in_list?(order)
    Order::EDITABLE_STATUSES.include?(order.status) && order.sendit_code.blank? && order.external_order_receipt.nil?
  end
end
