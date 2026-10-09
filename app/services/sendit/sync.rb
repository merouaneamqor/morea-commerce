# frozen_string_literal: true

module Sendit
  # Keeps an Order and its Sendit parcel ("colis") in step
  class Sync
    # Official codes from GET /all-status-deliveries (API returns TOPICKUP; we normalize to TO_PICKUP)
    LABELS = {
      "PENDING" => "En attente",
      "TO_PREPARE" => "À préparer",
      "NEW_DESTINATION" => "À changer",
      "TO_PICKUP" => "Ramassage en cours",
      "PICKEDUP" => "Ramassé",
      "WAREHOUSE" => "Entrepôt",
      "TRANSIT" => "En transit",
      "DISTRIBUTED" => "Distribué",
      "UNREACHABLE" => "Injoignable",
      "POSTPONED" => "Reporté",
      "DELIVERING" => "En cours de livraison",
      "DELIVERED" => "Livré",
      "CANCELED" => "Annulé",
      "REJECTED" => "Refusé"
    }.freeze

    RETURN_LABELS = {
      "RETOUR_PENDING" => "Retour en attente",
      "TORETURN" => "Retour en route",
      "RETURN_WAREHOUSE" => "Retour à l'entrepôt",
      "RETURN_TOCHECK" => "Retour à vérifier",
      "RETURN_STOCK" => "Retour en stock",
      "RETURN_SELLER" => "Retourné au vendeur"
    }.freeze
    RETURN_DONE = %w[RETURN_STOCK RETURN_SELLER].freeze

    # Discord when the courier can't finish or the address must change
    ALERT_STATUSES = %w[NEW_DESTINATION UNREACHABLE POSTPONED REJECTED].freeze

    # Morea order status each Sendit code implies (orders never move backwards on FLOW).
    ORDER_STATUS = {
      "PENDING" => "confirmed",               # parcel exists ⇒ at least confirmed
      "TO_PREPARE" => "preparing",
      "NEW_DESTINATION" => "address_issue",
      "TO_PICKUP" => "awaiting_pickup",
      "PICKEDUP" => "picked_up",
      "WAREHOUSE" => "in_transit",
      "TRANSIT" => "in_transit",
      "DISTRIBUTED" => "out_for_delivery",
      "UNREACHABLE" => "unreachable",
      "POSTPONED" => "postponed",
      "DELIVERING" => "out_for_delivery",
      "DELIVERED" => "delivered",
      "CANCELED" => "cancelled",
      "REJECTED" => "returned"
    }.freeze

    FINAL = %w[DELIVERED CANCELED REJECTED].freeze
    STATUSES = LABELS.keys.freeze

    def self.normalize_status(status)
      status = status.to_s.upcase
      case status
      when "TOPICKUP" then "TO_PICKUP"
      when "CANCELLED" then "CANCELED"
      else status
      end
    end

    def self.label(status)
      key = normalize_status(status)
      LABELS.fetch(key, status.to_s.humanize)
    end

    def self.return_label(status)
      RETURN_LABELS.fetch(status.to_s.upcase, status.to_s.humanize) if status.present?
    end

    # Refresh French labels from Sendit when reachable (falls back to LABELS)
    def self.labels_for(store)
      return LABELS unless Client.configured?(store)

      Rails.cache.fetch("sendit:status_labels:store:#{store.id}", expires_in: 1.day) do
        remote = Client.new(store).all_status_deliveries
        next LABELS if remote.blank?

        LABELS.merge(remote.transform_keys { |k| normalize_status(k) }.slice(*STATUSES))
      end
    rescue StandardError => e
      Rails.logger.warn("[Sendit] status labels unavailable: #{e.message}")
      LABELS
    end

    # Orders that should have a parcel but don't, parcels still on the road,
    # and refused/cancelled parcels whose return hasn't reached the seller yet
    def self.pending_orders(scope = Order.all)
      to_push = scope.where(status: %w[confirmed preparing awaiting_pickup address_issue], sendit_code: nil)
      # Skip local terminals — no point refreshing a delivered/cancelled order forever
      in_progress = scope.where.not(sendit_code: nil)
                         .where("sendit_status IS NULL OR sendit_status NOT IN (?)", FINAL)
                         .where.not(status: %w[delivered cancelled returned])
      returning = scope.where.not(sendit_code: nil).where(sendit_status: %w[REJECTED CANCELED])
                       .where("sendit_return_status IS NULL OR sendit_return_status NOT IN (?)", RETURN_DONE)
                       .where.not(status: "cancelled")
      [ to_push, in_progress.or(returning) ]
    end

    # Re-project local status from already-stored Sendit codes (no API call).
    # Used after mapping changes and at the start of enqueue_all.
    def self.reapply_stored!(scope = Order.all)
      scope.where.not(sendit_status: [ nil, "" ]).find_each do |order|
        next if order.status.in?(%w[delivered cancelled])

        new(order).apply_status!(
          order.sendit_status,
          message: order.sendit_message,
          fee: order.sendit_fee,
          return_status: order.sendit_return_status
        )
      rescue StandardError => e
        Rails.logger.warn("[Sendit] reapply failed for #{order.number}: #{e.message}")
      end
    end

    def self.enqueue_all(scope = Order.all)
      reapply_stored!(scope)
      to_push, to_refresh = pending_orders(scope)
      to_push.find_each { |o| SenditSyncJob.perform_later(o.id, "push") }
      to_refresh.find_each { |o| SenditSyncJob.perform_later(o.id, "refresh") }
      to_push.count + to_refresh.count
    end

    def initialize(order, client: nil)
      @order = order
      @client = client || Client.new(order.store)
    end

    attr_reader :order

    # Create the parcel on Sendit (idempotent: skipped when the order already has one)
    def push!
      return order if order.sendit_code.present?
      return order if order.status.in?(%w[cancelled returned delivered])

      district = resolve_district!
      raise Client::Error, "Choose the Sendit pickup city in Settings › Shipping before sending parcels." if pickup_district_id.blank?

      data = @client.create_delivery(delivery_payload(district))
      order.update!(sendit_code: data["code"], sendit_error: nil, sendit_district_id: district[:id], sendit_district_name: district[:name])
      apply_remote!(data)
      order
    rescue Client::Error => e
      fail!(e.message)
    end

    def refresh!
      return order if order.sendit_code.blank? && order.status.in?(%w[cancelled returned delivered])
      return push! if order.sendit_code.blank?

      apply_remote!(@client.delivery(order.sendit_code))
      order
    rescue Client::Error => e
      fail!(e.message)
    end

    # Remove the parcel if Sendit hasn't collected it yet.
    # bang: true raises so Morea cancel can abort when the courier delete fails.
    def cancel!(bang: false)
      return order if order.sendit_code.blank?
      return order if self.class.normalize_status(order.sendit_status) == "CANCELED"

      unless cancellable?
        msg = "Parcel #{order.sendit_code} is already #{self.class.label(order.sendit_status)} — cancel it from Sendit."
        fail!(msg)
        raise Client::Error, msg if bang
        return order
      end

      @client.delete_delivery(order.sendit_code)
      order.update!(sendit_status: "CANCELED", sendit_error: nil, sendit_synced_at: Time.current)
      order
    rescue Client::Error => e
      fail!(e.message)
      raise if bang
      order
    end

    # Push address / amount / products to a parcel that hasn't left the warehouse yet
    def update!
      return order if order.sendit_code.blank?
      return fail!("Parcel #{order.sendit_code} is already #{self.class.label(order.sendit_status)} — update it from Sendit.") unless cancellable?

      district = resolve_district!
      data = @client.update_delivery(order.sendit_code, delivery_payload(district))
      order.update!(sendit_error: nil, sendit_district_id: district[:id], sendit_district_name: district[:name], sendit_synced_at: Time.current)
      apply_remote!(data) if data.is_a?(Hash) && data["status"].present?
      order
    rescue Client::Error => e
      fail!(e.message)
    end

    def cancellable?
      status = self.class.normalize_status(order.sendit_status)
      status.blank? || %w[PENDING TO_PREPARE TO_PICKUP NEW_DESTINATION].include?(status)
    end

    def label_url
      return if order.sendit_code.blank?

      @client.labels(order.sendit_code)["fileUrl"]
    end

    # Webhook / refresh: record the Sendit status and advance the order accordingly
    def apply_status!(status, message: nil, deliver_by: nil, fee: nil, return_status: nil)
      status = self.class.normalize_status(status)
      previous = [ order.sendit_status, order.sendit_return_status ]
      order.update!(
        sendit_return_status: return_status.presence || order.sendit_return_status,
        sendit_status: status,
        sendit_message: message.presence || order.sendit_message,
        sendit_deliver_by: (Date.parse(deliver_by.to_s) rescue order.sendit_deliver_by),
        sendit_fee: fee.presence || order.sendit_fee,
        sendit_error: nil,
        sendit_synced_at: Time.current
      )

      target = ORDER_STATUS.fetch(status, :unknown)
      ret = order.sendit_return_status.to_s.upcase
      if order.status != "cancelled" && RETURN_LABELS.key?(ret)
        target = "returned"
      end

      reason = message.presence || self.class.label(status)
      if target == :unknown
        Rails.logger.warn("[Sendit] Unknown status #{status.inspect} for #{order.number}")
      elsif target == "cancelled"
        if order.can_transition_to?("cancelled")
          order.transition_to!("cancelled", reason: reason, source: :sendit)
        elsif order.status != "cancelled"
          # Already with courier — cancel on Sendit means the parcel is coming back
          order.move_to_status!("returned", reason: reason)
        end
      elsif target == "returned"
        order.advance_to!("picked_up")
        order.move_to_status!("returned", reason: reason)
      elsif target
        order.move_to_status!(target, reason: reason)
      end

      alert_if_notable(previous)
      order
    end

    private

    def apply_remote!(data)
      apply_status!(data["status"], fee: data["fee"], return_status: data["status_return"])
    end

    def alert_if_notable(previous)
      current = [ order.sendit_status, order.sendit_return_status ]
      return if current == previous

      status_alert = ALERT_STATUSES.include?(order.sendit_status) && order.sendit_status != previous.first
      return_alert = RETURN_DONE.include?(order.sendit_return_status) && order.sendit_return_status != previous.last
      return unless status_alert || return_alert

      text = return_alert ? self.class.return_label(order.sendit_return_status) : self.class.label(order.sendit_status)
      DiscordNotifier.notify_delivery_update(order, text)
    rescue StandardError => e
      Rails.logger.warn("[Sendit] alert failed for #{order.number}: #{e.message}")
    end

    def resolve_district!
      if order.sendit_district_id.present?
        Districts.find(order.sendit_district_id, store: order.store) || { id: order.sendit_district_id, name: order.sendit_district_name }
      else
        Districts.match(store: order.store, city: order.customer_city, address: "#{order.customer_district} #{order.customer_address}") ||
          raise(Client::Error, "No Sendit city matches “#{order.customer_city}”. Choose the Sendit city on the order, then retry.")
      end
    end

    def delivery_payload(district)
      {
        pickup_district_id: pickup_district_id,
        district_id: district[:id],
        name: order.customer_name,
        amount: (order.total_cents / 100.0).round(2),
        address: order.delivery_address,
        phone: local_phone(order.customer_phone),
        comment: order.notes.to_s.truncate(250).presence,
        reference: order.number,
        allow_open: order.store.sendit_allow_open? ? 1 : 0,
        allow_try: order.store.sendit_allow_try? ? 1 : 0,
        products_from_stock: 0,
        products: order.order_items.map { |i| [ i.product_name, i.variant_name.presence ].compact.join(" ") + " x#{i.quantity}" }.join("; "),
        option_exchange: 0
      }.compact
    end

    def pickup_district_id
      order.store.sendit_pickup_district_id.presence
    end

    # +212 6 12 34 56 78 -> 0612345678
    def local_phone(phone)
      digits = phone.to_s.gsub(/\D/, "")
      digits = "0#{digits.delete_prefix("212")}" if digits.start_with?("212") && digits.length == 12
      digits
    end

    def fail!(message)
      order.update_columns(sendit_error: message.to_s.truncate(500), sendit_synced_at: Time.current, updated_at: Time.current)
      Rails.logger.warn("[Sendit] #{order.number}: #{message}")
      order
    end
  end
end
