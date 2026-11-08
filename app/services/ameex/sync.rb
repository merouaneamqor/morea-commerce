# frozen_string_literal: true

module Ameex
  # Keeps an Order and its Ameex parcel in step.
  class Sync
    LABELS = {
      "NEW_PARCEL" => "Nouveau colis",
      "WAITING_PICKUP" => "Attente de ramassage",
      "PICKED_UP" => "Ramassé",
      "IN_PROGRESS" => "En cours",
      "DELIVERED" => "Livré",
      "RETURNED" => "Retourné",
      "REFUSED" => "Refusé",
      "REFUSE" => "Refusé",
      "CANCELED" => "Annulé",
      "CANCELLED" => "Annulé",
      "POSTPONED" => "Reporté",
      "UNREACHABLE" => "Injoignable",
      "NOANSWER" => "Pas de réponse",
      "OUT_OF_AREA" => "Hors-zone"
    }.freeze

    ORDER_STATUS = {
      "NEW_PARCEL" => "confirmed",
      "WAITING_PICKUP" => "awaiting_pickup",
      "PICKED_UP" => "picked_up",
      "IN_PROGRESS" => "out_for_delivery",
      "DELIVERED" => "delivered",
      "RETURNED" => "returned",
      "REFUSED" => "returned",
      "REFUSE" => "returned",
      "CANCELED" => "cancelled",
      "CANCELLED" => "cancelled",
      "POSTPONED" => "postponed",
      "UNREACHABLE" => "unreachable",
      "NOANSWER" => "unreachable",
      "OUT_OF_AREA" => "address_issue"
    }.freeze

    FINAL = %w[DELIVERED RETURNED REFUSED REFUSE CANCELED CANCELLED].freeze
    ALERT_STATUSES = %w[UNREACHABLE POSTPONED REFUSED REFUSE OUT_OF_AREA NOANSWER].freeze

    def self.normalize_status(status)
      key = status.to_s.upcase.tr("-", "_")
      key == "CANCELLED" ? "CANCELED" : key
    end

    def self.label(status)
      key = normalize_status(status)
      LABELS.fetch(key, status.to_s.humanize)
    end

    def self.pending_orders(scope = Order.all)
      to_push = scope.where(status: %w[confirmed preparing awaiting_pickup address_issue], ameex_code: nil, sendit_code: nil, ozon_code: nil)
      in_progress = scope.where.not(ameex_code: nil)
                        .where("ameex_status IS NULL OR ameex_status NOT IN (?)", FINAL)
                        .where.not(status: %w[delivered cancelled returned])
      returning = scope.where.not(ameex_code: nil).where(ameex_status: %w[RETURNED REFUSED REFUSE CANCELED CANCELLED])
                       .where.not(status: "cancelled")
      [ to_push, in_progress.or(returning) ]
    end

    def self.reapply_stored!(scope = Order.all)
      scope.where.not(ameex_status: [ nil, "" ]).find_each do |order|
        next if order.status.in?(%w[delivered cancelled])

        new(order).apply_status!(order.ameex_status, message: order.ameex_message, fee: order.ameex_fee)
      rescue StandardError => e
        Rails.logger.warn("[Ameex] reapply failed for #{order.number}: #{e.message}")
      end
    end

    def self.enqueue_all(scope = Order.all)
      reapply_stored!(scope)
      to_push, to_refresh = pending_orders(scope)
      to_push.find_each { |o| AmeexSyncJob.perform_later(o.id, "push") }
      to_refresh.find_each { |o| AmeexSyncJob.perform_later(o.id, "refresh") }
      to_push.count + to_refresh.count
    end

    def initialize(order, client: nil)
      @order = order
      @client = client || Client.new(order.store)
    end

    attr_reader :order

    def push!
      return fail!(I18n.t("import_contact.blocked")) if order.reload.contact_review_required?
      return order if [ order.ameex_code, order.sendit_code, order.ozon_code ].any?(&:present?)
      return order if order.status.in?(%w[cancelled returned delivered])

      city = resolve_city!
      data = @client.add_parcel(parcel_payload(city))
      code = extract_code(data)
      raise Client::Error.new("Ameex returned no parcel code", kind: :unexpected, detail: data.keys.join(",")) if code.blank?

      order.update!(
        ameex_code: code,
        ameex_error: nil,
        ameex_city_id: city[:id],
        ameex_city_name: city[:name]
      )
      apply_status!(extract_status(data) || "NEW_PARCEL", message: data["comment"] || data["COMMENT"])
      order
    rescue Client::Error => e
      fail!(e.message)
    end

    def refresh!
      return order if order.ameex_code.blank? && order.status.in?(%w[cancelled returned delivered])
      return push! if order.ameex_code.blank?

      data = @client.tracking(order.ameex_code)
      status = extract_status(data)
      raise Client::Error.new("Ameex returned no status for #{order.ameex_code}", kind: :unexpected) if status.blank?

      apply_status!(status, message: data["COMMENT"] || data["comment"] || data["STATUT_NAME"] || data["statut_name"])
      order
    rescue Client::Error => e
      fail!(e.message)
    end

    def cancel!
      return order if order.ameex_code.blank?
      return order if self.class.normalize_status(order.ameex_status) == "CANCELED"

      apply_status!("CANCELED", message: "Cancelled in Seallo")
      order
    end

    def cancellable?
      status = self.class.normalize_status(order.ameex_status)
      status.blank? || %w[NEW_PARCEL WAITING_PICKUP].include?(status)
    end

    def apply_status!(status, message: nil, fee: nil)
      status = self.class.normalize_status(status)
      previous = order.ameex_status
      order.update!(
        ameex_status: status,
        ameex_message: message.presence || order.ameex_message,
        ameex_fee: fee.presence || order.ameex_fee,
        ameex_error: nil,
        ameex_synced_at: Time.current
      )
      order.freeze_fees!

      target = ORDER_STATUS.fetch(status, :unknown)
      reason = message.presence || self.class.label(status)
      if target == :unknown
        Rails.logger.warn("[Ameex] Unknown status #{status.inspect} for #{order.number}")
      elsif target == "cancelled"
        if order.can_transition_to?("cancelled")
          order.transition_to!("cancelled", reason: reason, source: :ameex, sync_delivery: false)
        elsif order.status != "cancelled"
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

    def extract_code(data)
      return if data.blank?

      data["CODE"].presence || data["code"].presence || data["parcel_code"].presence || data["ParcelCode"].presence ||
        data.dig("data", "CODE") || data.dig("data", "code") || data.dig("data", "parcel_code")
    end

    def extract_status(data)
      return if data.blank?

      data["STATUT"].presence || data["statut"].presence || data["status"].presence || data["STATUS"].presence ||
        data.dig("data", "STATUT") || data.dig("data", "status")
    end

    def alert_if_notable(previous)
      return if order.ameex_status == previous
      return unless ALERT_STATUSES.include?(order.ameex_status)

      DiscordNotifier.notify_delivery_update(order, self.class.label(order.ameex_status))
    rescue StandardError => e
      Rails.logger.warn("[Ameex] alert failed for #{order.number}: #{e.message}")
    end

    def resolve_city!
      if order.ameex_city_id.present?
        Cities.find(order.ameex_city_id, store: order.store) || { id: order.ameex_city_id, name: order.ameex_city_name }
      else
        Cities.match(store: order.store, city: order.customer_city) ||
          raise(Client::Error, "No Ameex city matches “#{order.customer_city}”. Choose the Ameex city on the order, then retry.")
      end
    end

    def parcel_payload(city)
      {
        type: "SIMPLE",
        receiver: order.customer_name,
        phone: local_phone(order.customer_phone),
        city: city[:id],
        cod: (order.total_cents / 100.0).round(2),
        address: order.delivery_address,
        product: order.order_items.map { |i| [ i.product_name, i.variant_name.presence ].compact.join(" ") + " x#{i.quantity}" }.join("; ").truncate(250).presence,
        comment: order.notes.to_s.truncate(250).presence,
        order_num: order.number
      }.compact
    end

    def local_phone(phone)
      digits = phone.to_s.gsub(/\D/, "")
      digits = "0#{digits.delete_prefix("212")}" if digits.start_with?("212") && digits.length == 12
      digits
    end

    def fail!(message)
      order.update_columns(ameex_error: message.to_s.truncate(500), ameex_synced_at: Time.current, updated_at: Time.current)
      Rails.logger.warn("[Ameex] #{order.number}: #{message}")
      order
    end
  end
end
