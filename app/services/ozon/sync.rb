# frozen_string_literal: true

module Ozon
  # Keeps an Order and its Ozon Express parcel in step.
  class Sync
    LABELS = {
      "NEW_PARCEL" => "Nouveau colis",
      "WAITING_PICKUP" => "Attente de ramassage",
      "PRE_PICKED_UP" => "Pré-ramassé",
      "PICKED_UP" => "Ramassé",
      "SENT" => "Expédié",
      "ONV" => "En voyage",
      "RECEIVED" => "Reçu",
      "DISTRIBUTION" => "Mise en distribution",
      "IN_PROGRESS" => "En cours",
      "SENT_TO_AGENCY" => "Envoyé à l'agence",
      "RECEIVED_IN_AGENCY" => "Reçu en agence",
      "DELIVERED" => "Livré",
      "RETURNED" => "Retourné",
      "REFUSE" => "Refusé",
      "DECLINED" => "Refusé",
      "CANCELED" => "Annulé",
      "CANCELED_TEAM" => "Annulé (suivi)",
      "POSTPONED" => "Reporté",
      "POSTPONED_TEAM" => "Reporté (suivi)",
      "RPO" => "Reporté aujourd'hui",
      "PROGRAMED" => "Programmé",
      "NOANSWER" => "Pas de réponse",
      "NOANSWER_TEAM" => "Pas de réponse (suivi)",
      "NOANSWER_DAY_2" => "Pas de réponse J+2",
      "NOANSWER_DAY_3" => "Pas de réponse J+3",
      "UNREACHABLE" => "Injoignable",
      "UNREACHABLE_TEAM" => "Injoignable (suivi)",
      "VOICEMAIL" => "Boîte vocale",
      "VOICEMAIL_TEAM" => "Boîte vocale (suivi)",
      "OUT_OF_AREA" => "Hors-zone",
      "SCTR" => "Hors secteur",
      "NCVRT" => "Zone non couverte",
      "SANS_ADRE" => "Sans adresse",
      "EN" => "Erreur numéro",
      "DEPLA" => "Pas de réponse + déplacement",
      "DEPLA_DAY_2" => "Pas de réponse + déplacement J+2",
      "DEPLA_DAY_3" => "Pas de réponse + déplacement J+3",
      "REMBOURSED" => "Remboursé",
      "DAMAGED" => "Endommagé",
      "DELAYED" => "Retardé",
      "VLMN" => "Retard livraison 48h-72h",
      "SENT_BY_AMANA" => "Expédié par AMANA",
      "RETURN_BY_AMANA" => "Retour par AMANA",
      "INT" => "Client intéressé",
      "BAM_SEIZED" => "Saisi par Barid Al-Maghrib"
    }.freeze

    ORDER_STATUS = {
      "NEW_PARCEL" => "confirmed",
      "WAITING_PICKUP" => "awaiting_pickup",
      "PRE_PICKED_UP" => "awaiting_pickup",
      "PICKED_UP" => "picked_up",
      "SENT" => "in_transit",
      "ONV" => "in_transit",
      "RECEIVED" => "in_transit",
      "DISTRIBUTION" => "out_for_delivery",
      "IN_PROGRESS" => "out_for_delivery",
      "SENT_TO_AGENCY" => "in_transit",
      "RECEIVED_IN_AGENCY" => "in_transit",
      "SENT_BY_AMANA" => "in_transit",
      "DELIVERED" => "delivered",
      "RETURNED" => "returned",
      "RETURN_BY_AMANA" => "returned",
      "REFUSE" => "returned",
      "DECLINED" => "returned",
      "REMBOURSED" => "returned",
      "CANCELED" => "cancelled",
      "CANCELED_TEAM" => "cancelled",
      "POSTPONED" => "postponed",
      "POSTPONED_TEAM" => "postponed",
      "RPO" => "postponed",
      "PROGRAMED" => "postponed",
      "DELAYED" => "postponed",
      "VLMN" => "postponed",
      "NOANSWER" => "unreachable",
      "NOANSWER_TEAM" => "unreachable",
      "NOANSWER_DAY_2" => "unreachable",
      "NOANSWER_DAY_3" => "unreachable",
      "UNREACHABLE" => "unreachable",
      "UNREACHABLE_TEAM" => "unreachable",
      "VOICEMAIL" => "unreachable",
      "VOICEMAIL_TEAM" => "unreachable",
      "DEPLA" => "unreachable",
      "DEPLA_DAY_2" => "unreachable",
      "DEPLA_DAY_3" => "unreachable",
      "OUT_OF_AREA" => "address_issue",
      "SCTR" => "address_issue",
      "NCVRT" => "address_issue",
      "SANS_ADRE" => "address_issue",
      "EN" => "address_issue",
      "DAMAGED" => "returned",
      "BAM_SEIZED" => "returned",
      "INT" => "out_for_delivery"
    }.freeze

    FINAL = %w[DELIVERED RETURNED REFUSE DECLINED CANCELED CANCELED_TEAM REMBOURSED].freeze
    ALERT_STATUSES = %w[UNREACHABLE UNREACHABLE_TEAM POSTPONED POSTPONED_TEAM REFUSE DECLINED OUT_OF_AREA SANS_ADRE EN NOANSWER].freeze
    STATUSES = LABELS.keys.freeze

    def self.normalize_status(status)
      status.to_s.upcase.tr("-", "_")
    end

    def self.label(status)
      key = normalize_status(status)
      LABELS.fetch(key, status.to_s.humanize)
    end

    def self.pending_orders(scope = Order.all)
      to_push = scope.where(status: %w[confirmed preparing awaiting_pickup address_issue], ozon_code: nil, sendit_code: nil, ameex_code: nil)
      in_progress = scope.where.not(ozon_code: nil)
                        .where("ozon_status IS NULL OR ozon_status NOT IN (?)", FINAL)
                        .where.not(status: %w[delivered cancelled returned])
      returning = scope.where.not(ozon_code: nil).where(ozon_status: %w[RETURNED REFUSE DECLINED CANCELED CANCELED_TEAM])
                       .where.not(status: "cancelled")
      [ to_push, in_progress.or(returning) ]
    end

    def self.reapply_stored!(scope = Order.all)
      scope.where.not(ozon_status: [ nil, "" ]).find_each do |order|
        next if order.status.in?(%w[delivered cancelled])

        new(order).apply_status!(order.ozon_status, message: order.ozon_message, fee: order.ozon_fee)
      rescue StandardError => e
        Rails.logger.warn("[Ozon] reapply failed for #{order.number}: #{e.message}")
      end
    end

    def self.enqueue_all(scope = Order.all)
      reapply_stored!(scope)
      to_push, to_refresh = pending_orders(scope)
      to_push.find_each { |o| OzonSyncJob.perform_later(o.id, "push") }
      to_refresh.find_each { |o| OzonSyncJob.perform_later(o.id, "refresh") }
      to_push.count + to_refresh.count
    end

    def initialize(order, client: nil)
      @order = order
      @client = client || Client.new(order.store)
    end

    attr_reader :order

    def push!
      return fail!(I18n.t("import_contact.blocked")) if order.reload.contact_review_required?
      return order if [ order.ozon_code, order.sendit_code, order.ameex_code ].any?(&:present?)
      return order if order.status.in?(%w[cancelled returned delivered])

      city = resolve_city!
      data = @client.add_parcel(parcel_payload(city))
      code = data["TRACKING-NUMBER"].presence || data["tracking-number"].presence || data["TRACKING_NUMBER"]
      raise Client::Error.new("Ozon returned no tracking number", kind: :unexpected, detail: data.keys.join(",")) if code.blank?

      fee = data["DELIVERED-PRICE"].presence || data["delivered-price"]
      order.update!(
        ozon_code: code,
        ozon_error: nil,
        ozon_city_id: city[:id],
        ozon_city_name: data["CITY_NAME"].presence || city[:name],
        ozon_fee: fee.presence || order.ozon_fee
      )
      status = extract_status(data) || "NEW_PARCEL"
      apply_status!(status, message: data["NOTE"] || data["note"], fee: fee)
      order
    rescue Client::Error => e
      fail!(e.message)
    end

    def refresh!
      return order if order.ozon_code.blank? && order.status.in?(%w[cancelled returned delivered])
      return push! if order.ozon_code.blank?

      info = @client.parcel_info(order.ozon_code)
      status = extract_status(info)
      if status.blank?
        tracking = @client.tracking(order.ozon_code)
        status = extract_status(tracking)
      end
      raise Client::Error.new("Ozon returned no status for #{order.ozon_code}", kind: :unexpected) if status.blank?

      fee = info["DELIVERED-PRICE"].presence || info["delivered-price"] || order.ozon_fee
      apply_status!(status, message: info["NOTE"] || info["note"] || info["COMMENT"], fee: fee)
      order
    rescue Client::Error => e
      fail!(e.message)
    end

    # Ozon has no delete-parcel API in the public contract — mark cancelled locally only.
    def cancel!
      return order if order.ozon_code.blank?
      return order if self.class.normalize_status(order.ozon_status) == "CANCELED"

      apply_status!("CANCELED", message: "Cancelled in Seallo")
      order
    end

    def cancellable?
      status = self.class.normalize_status(order.ozon_status)
      status.blank? || %w[NEW_PARCEL WAITING_PICKUP PRE_PICKED_UP].include?(status)
    end

    # Create a one-parcel delivery note and return the standard PDF URL.
    def label_url
      return if order.ozon_code.blank?

      created = @client.add_delivery_note
      ref = created["ref"].presence || created["REF"].presence || created["dn-ref"]
      raise Client::Error.new("Ozon returned no delivery-note ref", kind: :unexpected) if ref.blank?

      @client.add_parcel_to_delivery_note(ref: ref, codes: [ order.ozon_code ])
      @client.save_delivery_note(ref)
      @client.delivery_note_pdf_url(ref, format: :tickets_4x4)
    end

    def apply_status!(status, message: nil, fee: nil)
      status = self.class.normalize_status(status)
      previous = order.ozon_status
      order.update!(
        ozon_status: status,
        ozon_message: message.presence || order.ozon_message,
        ozon_fee: fee.presence || order.ozon_fee,
        ozon_error: nil,
        ozon_synced_at: Time.current
      )
      order.freeze_fees!

      target = ORDER_STATUS.fetch(status, :unknown)
      reason = message.presence || self.class.label(status)
      if target == :unknown
        Rails.logger.warn("[Ozon] Unknown status #{status.inspect} for #{order.number}")
      elsif target == "cancelled"
        if order.can_transition_to?("cancelled")
          order.transition_to!("cancelled", reason: reason, source: :ozon, sync_delivery: false)
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

    def extract_status(data)
      return if data.blank?

      value = data["orderStatus"] || data["ORDER_STATUS"] || data["STATUS"] || data["LAST-STATUS"] ||
        data["LAST_STATUS"] || data["statut"] || data["STATUT"]
      if value.blank? && data["TRACKING"].is_a?(Hash)
        value = data["TRACKING"]["STATUS"] || data["TRACKING"]["orderStatus"]
      end
      if value.blank? && data.values.first.is_a?(Hash)
        nested = data.values.find { |v| v.is_a?(Hash) && (v["STATUS"] || v["orderStatus"] || v["STATUT"]) }
        value = nested && (nested["STATUS"] || nested["orderStatus"] || nested["STATUT"])
      end
      value.presence
    end

    def alert_if_notable(previous)
      return if order.ozon_status == previous
      return unless ALERT_STATUSES.include?(order.ozon_status)

      DiscordNotifier.notify_delivery_update(order, self.class.label(order.ozon_status))
    rescue StandardError => e
      Rails.logger.warn("[Ozon] alert failed for #{order.number}: #{e.message}")
    end

    def resolve_city!
      if order.ozon_city_id.present?
        Cities.find(order.ozon_city_id, store: order.store) || { id: order.ozon_city_id, name: order.ozon_city_name }
      else
        Cities.match(store: order.store, city: order.customer_city) ||
          raise(Client::Error, "No Ozon city matches “#{order.customer_city}”. Choose the Ozon city on the order, then retry.")
      end
    end

    def parcel_payload(city)
      account = order.store.ozon_delivery_account
      {
        "tracking-number" => order.number,
        "parcel-receiver" => order.customer_name,
        "parcel-phone" => local_phone(order.customer_phone),
        "parcel-city" => city[:id],
        "parcel-address" => order.delivery_address,
        "parcel-note" => order.notes.to_s.truncate(250).presence,
        "parcel-price" => (order.total_cents / 100.0).round(2),
        "parcel-nature" => order.order_items.map { |i| [ i.product_name, i.variant_name.presence ].compact.join(" ") + " x#{i.quantity}" }.join("; ").truncate(250).presence,
        "parcel-stock" => "0",
        "parcel-open" => account&.allow_open == false ? "2" : "1",
        "parcel-fragile" => "0",
        "parcel-replace" => "0"
      }.compact
    end

    def local_phone(phone)
      digits = phone.to_s.gsub(/\D/, "")
      digits = "0#{digits.delete_prefix("212")}" if digits.start_with?("212") && digits.length == 12
      digits
    end

    def fail!(message)
      order.update_columns(ozon_error: message.to_s.truncate(500), ozon_synced_at: Time.current, updated_at: Time.current)
      Rails.logger.warn("[Ozon] #{order.number}: #{message}")
      order
    end
  end
end
