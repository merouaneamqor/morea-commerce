# frozen_string_literal: true

module Ameex
  # Keeps an Order and its Ameex parcel in step.
  # Status catalog: GET /Delivery/Parcels/Statuts → api.data.status
  class Sync
    LABELS = {
      "NEW_PARCEL" => "Nouveau Colis",
      "DRAFT" => "Brouillon",
      "WAITING_PICKUP" => "Attente De Ramassage",
      "PICKED_UP" => "Ramassé",
      "SENT" => "Expédié",
      "TRAVELLING" => "En Voyage",
      "IN_SHIPMENT" => "En cours d'expédition",
      "RECEIVED" => "Reçu",
      "DISTRIBUTION" => "Mise en distribution",
      "DISPOSITION" => "Mis à disposition",
      "IN_PROGRESS" => "En cours",
      "CONFIRMED_BY_LIVREUR" => "Confirmé Par Livreur",
      "DELIVERED" => "Livré",
      "RETURNED" => "Retourné",
      "PREPAR_RETURN" => "PRÉPARATION RETOUR",
      "REFUSE" => "Refusé",
      "REFUNDED" => "Remboursé",
      "CANCELED" => "Annulé",
      "CANCELED_TEAM" => "Annulé ( Suivi )",
      "POSTPONED" => "Reporté",
      "POSTPONED_TEAM" => "Reporté ( Suivi )",
      "SCHEDULED" => "Programmé",
      "NO_ANSWER" => "Pas de réponse",
      "NO_ANSWER_SMS" => "Pas de réponse + SMS",
      "NO_ANSWER_TEAM" => "Pas de réponse ( Suivi )",
      "UNREACHABLE" => "Injoignable",
      "UNREACHABLE_TEAM" => "Injoignable ( Suivi )",
      "VOICEMAIL" => "Boîte vocale",
      "VOICEMAIL_TEAM" => "Boîte vocale ( Suivi )",
      "OUT_OF_AREA" => "Hors-zone",
      "WRONG_NUMBER" => "Numéro Incorrect",
      "DOESNT_ORDER" => "Client n'a pas commandé",
      "RELAUNCH" => "Relancer",
      "RELAUNCH_NEW" => "Relancer vers un nouveau client",
      "RELAUNCH_TEAM" => "Relancer ( Suivi )",
      "RESEND_NEW_CITY" => "Renvoyez vers nouvelle ville"
    }.freeze

    ORDER_STATUS = {
      "NEW_PARCEL" => "confirmed",
      "DRAFT" => "confirmed",
      "WAITING_PICKUP" => "awaiting_pickup",
      "PICKED_UP" => "picked_up",
      "SENT" => "in_transit",
      "TRAVELLING" => "in_transit",
      "IN_SHIPMENT" => "in_transit",
      "RECEIVED" => "in_transit",
      "DISTRIBUTION" => "out_for_delivery",
      "DISPOSITION" => "out_for_delivery",
      "IN_PROGRESS" => "out_for_delivery",
      "CONFIRMED_BY_LIVREUR" => "out_for_delivery",
      "RELAUNCH" => "out_for_delivery",
      "RELAUNCH_NEW" => "out_for_delivery",
      "RELAUNCH_TEAM" => "out_for_delivery",
      "RESEND_NEW_CITY" => "address_issue",
      "DELIVERED" => "delivered",
      "RETURNED" => "returned",
      "PREPAR_RETURN" => "returned",
      "REFUSE" => "returned",
      "REFUNDED" => "returned",
      "DOESNT_ORDER" => "returned",
      "CANCELED" => "cancelled",
      "CANCELED_TEAM" => "cancelled",
      "POSTPONED" => "postponed",
      "POSTPONED_TEAM" => "postponed",
      "SCHEDULED" => "postponed",
      "NO_ANSWER" => "unreachable",
      "NO_ANSWER_SMS" => "unreachable",
      "NO_ANSWER_TEAM" => "unreachable",
      "UNREACHABLE" => "unreachable",
      "UNREACHABLE_TEAM" => "unreachable",
      "VOICEMAIL" => "unreachable",
      "VOICEMAIL_TEAM" => "unreachable",
      "OUT_OF_AREA" => "address_issue",
      "WRONG_NUMBER" => "address_issue"
    }.freeze

    FINAL = %w[DELIVERED RETURNED REFUSE REFUNDED CANCELED CANCELED_TEAM DOESNT_ORDER].freeze
    ALERT_STATUSES = %w[UNREACHABLE UNREACHABLE_TEAM POSTPONED POSTPONED_TEAM REFUSE OUT_OF_AREA NO_ANSWER NO_ANSWER_SMS WRONG_NUMBER DOESNT_ORDER].freeze

    def self.normalize_status(status)
      key = status.to_s.upcase.tr("-", "_")
      case key
      when "CANCELLED" then "CANCELED"
      when "NOANSWER" then "NO_ANSWER"
      when "REFUSED" then "REFUSE"
      else key
      end
    end

    def self.label(status, store: nil)
      key = normalize_status(status)
      labels = store ? labels_for(store) : LABELS
      labels.fetch(key, status.to_s.humanize)
    end

    def self.labels_for(store)
      return LABELS unless Client.configured?(store)

      Rails.cache.fetch("ameex:status_labels:v2:store:#{store.id}", expires_in: 1.day) do
        remote = parse_status_catalog(Client.new(store).statuses)
        next LABELS if remote.blank?

        LABELS.merge(remote)
      end
    rescue StandardError => e
      Rails.logger.warn("[Ameex] status labels unavailable: #{e.message}")
      LABELS
    end

    def self.refresh_labels!(store)
      Rails.cache.delete("ameex:status_labels:v2:store:#{store.id}")
      labels_for(store)
    end

    def self.parse_status_catalog(raw)
      rows = raw.is_a?(Hash) ? raw : {}
      rows.each_with_object({}) do |(code, meta), map|
        key = normalize_status(code)
        name = meta.is_a?(Hash) ? (meta["name"] || meta["NAME"]).to_s : meta.to_s
        next if key.blank? || name.blank?

        map[key] = name
      end
    end
    private_class_method :parse_status_catalog

    def self.pending_orders(scope = Order.all)
      to_push = scope.where(status: %w[confirmed preparing awaiting_pickup address_issue], ameex_code: nil, sendit_code: nil, ozon_code: nil)
      in_progress = scope.where.not(ameex_code: nil)
                        .where("ameex_status IS NULL OR ameex_status NOT IN (?)", FINAL)
                        .where.not(status: %w[delivered cancelled returned])
      returning = scope.where.not(ameex_code: nil).where(ameex_status: %w[RETURNED REFUSE REFUNDED CANCELED CANCELED_TEAM PREPAR_RETURN])
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
      code = data["code"].presence || data["CODE"]
      raise Client::Error.new("Ameex returned no parcel code", kind: :unexpected, detail: data.keys.join(",")) if code.blank?

      order.update!(
        ameex_code: code,
        ameex_error: nil,
        ameex_city_id: city[:id],
        ameex_city_name: city[:name]
      )
      apply_status!("NEW_PARCEL", message: data["msg"])
      order
    rescue Client::Error => e
      fail!(e.message)
    end

    def refresh!
      return order if order.ameex_code.blank? && order.status.in?(%w[cancelled returned delivered])
      return push! if order.ameex_code.blank?

      info = @client.parcel_info(order.ameex_code)
      status = info["statut"].presence || info["STATUT"]
      if status.blank?
        tracking = @client.tracking(order.ameex_code)
        status = tracking["statut"].presence || tracking["STATUT"]
        message = tracking["comment"].presence || tracking["statut_name"]
      else
        message = info["statut_name"].presence || info["comment"]
      end
      raise Client::Error.new("Ameex returned no status for #{order.ameex_code}", kind: :unexpected) if status.blank?

      apply_status!(status, message: message)
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
      status.blank? || %w[NEW_PARCEL DRAFT WAITING_PICKUP].include?(status)
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
      reason = message.presence || self.class.label(status, store: order.store)
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

    def alert_if_notable(previous)
      return if order.ameex_status == previous
      return unless ALERT_STATUSES.include?(order.ameex_status)

      DiscordNotifier.notify_delivery_update(order, self.class.label(order.ameex_status, store: order.store))
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
