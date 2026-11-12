# frozen_string_literal: true

module Orders
  # The figures at the top of the Orders page (and the order distribution of the dashboard): the orders created in a date
  # range, counted two ways. One source for both pages, so the cards, the table and the dashboard always agree.
  #
  # Confirmation: every order created in the range is in exactly one of
  #   pending (new, waiting for a first or another call, or for a scheduled callback), confirmed (from the first
  #   confirmation on, whatever happened next), cancelled, wrong (the number is wrong or blocked).
  #   `planned` (a callback is scheduled) is counted apart so the dashboard can show it; the Orders page adds it to pending.
  # Shipping: the confirmed orders only, each in exactly one of
  #   to_ship (confirmed, preparing), in_transit (pickup planned, picked up, in transit, out for delivery),
  #   scheduled (delivery postponed), delivered, failed (unreachable customer, address issue), returned.
  # So confirmation.confirmed = shipping.values.sum, and total = pending + planned + confirmed + cancelled + wrong.
  #
  # scope: the orders to count (already limited to a workspace and, for an agent, to what she may see).
  # range: a DateRange (store days, inclusive end); the previous period is the same number of days just before.
  class Overview
    CONFIRMED_STATUSES = (Order::STATUSES - %w[new cancelled]).freeze
    SHIPPING_GROUPS = {
      "to_ship" => %w[confirmed preparing],
      "in_transit" => %w[awaiting_pickup picked_up in_transit out_for_delivery],
      "scheduled" => %w[postponed],
      "delivered" => %w[delivered],
      "failed" => %w[unreachable address_issue],
      "returned" => %w[returned]
    }.freeze

    def initialize(scope:, range:)
      @scope = scope
      @range = range
    end

    def total = status_counts.values.sum
    def previous_total = @scope.where(created_at: @range.previous.time_range).count

    # Percent change of the order count against the previous period; nil when that period had no order.
    def total_delta
      previous_total.positive? ? ((total - previous_total) * 100.0 / previous_total).round : nil
    end

    def confirmation
      @confirmation ||= begin
        new_total = status_counts.fetch("new", 0)
        planned = dispositions.fetch("callback", 0)
        wrong = dispositions.fetch("wrong_number", 0) + dispositions.fetch("blocked", 0)
        {
          pending: new_total - planned - wrong,
          planned: planned,
          confirmed: status_counts.slice(*CONFIRMED_STATUSES).values.sum,
          cancelled: status_counts.fetch("cancelled", 0),
          wrong: wrong
        }
      end
    end

    def shipping
      @shipping ||= SHIPPING_GROUPS.transform_values { |statuses| status_counts.slice(*statuses).values.sum }.symbolize_keys
    end

    # Whole percent of `count` in `whole`, rounded; nil when there is nothing to divide by.
    def self.percent(count, whole)
      whole.to_i.positive? ? (count * 100.0 / whole).round : nil
    end

    private

    def created = @scope.where(created_at: @range.time_range)
    def status_counts = @status_counts ||= created.group(:status).count

    def dispositions
      @dispositions ||= created.where(status: "new").left_joins(:order_confirmation).group("order_confirmations.disposition").count
    end
  end
end
