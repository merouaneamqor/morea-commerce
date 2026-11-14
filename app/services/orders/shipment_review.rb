# frozen_string_literal: true

module Orders
  # The confirmed orders that are waiting for a parcel at the delivery company, checked before anything is sent (the "Envoyer les colis confirmés" page).
  #
  # A confirmed order is ready to go unless:
  #   - its address or phone is incomplete, or its number is on the store's blocked list, or no delivery company can take it   (blocked: cannot be sent)
  #   - another order of the same number holds the same products (same lines and quantities), created within DUPLICATE_WINDOW and not cancelled or returned:
  #     it is a duplicate parcel. The first order of a pair stays, the later one is held back. An identical order that already has a parcel also holds this one back.   (blocked)
  #   - the customer already cancelled an order within CANCELLED_WINDOW   (a warning: the owner may still send it, it is not ticked by default)
  # The delivery company of an order is the one chosen on it (Sendit, Ozon Express, Ameex), or the store's only connected one; with several and no choice, the order waits for a choice.
  # Orders that already have a parcel code (at any company) are never offered again. Everything is read from this store only; the phone is compared on its last 9 digits.
  class ShipmentReview
    SHIPPABLE = %w[confirmed preparing].freeze
    DUPLICATE_WINDOW = 14.days
    CANCELLED_WINDOW = 365.days
    CARRIERS = %w[sendit ozon ameex].freeze
    PHONE_KEY_SQL = "right(regexp_replace(orders.customer_phone, '\\D', '', 'g'), 9)"

    Row = Struct.new(:order, :issues, :duplicate_of, :cancelled_count, :cancelled_last_at, :carrier, keyword_init: true) do
      def blocked? = (issues & %i[incomplete blocked duplicate no_company]).any?
      def warned? = issues.include?(:prior_cancelled)
      def ready? = issues.empty?
      def selectable? = !blocked?
      def checked_by_default? = ready?
    end

    attr_reader :store

    def initialize(store:, now: Time.current)
      @store = store
      @now = now
    end

    def rows
      @rows ||= build
    end

    def ready = rows.select(&:ready?)
    def warned = rows.select { |row| row.warned? && !row.blocked? }
    def blocked = rows.select(&:blocked?)
    def selectable = rows.select(&:selectable?)

    private

    def candidates
      @candidates ||= store.orders.active.where(status: SHIPPABLE).where(sendit_code: [ nil, "" ], ozon_code: [ nil, "" ], ameex_code: [ nil, "" ]).includes(:order_items).order(:created_at, :id).to_a
    end

    def key_for(phone) = BlockedPhone.key_for(phone)

    def build
      keys = candidates.map { |order| key_for(order.customer_phone) }.reject(&:blank?).uniq
      related = related_orders(keys)
      blocked_keys = BlockedPhone.where(store: store, phone_key: (keys + candidates.map { |order| key_for(order.second_phone) }.reject(&:blank?)).uniq).pluck(:phone_key).to_set

      candidates.map do |order|
        key = key_for(order.customer_phone)
        others = (related[key] || []).reject { |other| other.id == order.id }
        issues = []
        issues << :incomplete if incomplete?(order, key)
        carrier = carrier_for(order)
        issues << :no_company if carrier.nil?
        issues << :blocked if [ key, key_for(order.second_phone) ].any? { |k| k.present? && blocked_keys.include?(k) }
        twin = others.find { |other| duplicate?(order, other) }
        issues << :duplicate if twin
        cancelled = others.select { |other| other.status == "cancelled" && other.created_at >= @now - CANCELLED_WINDOW }
        issues << :prior_cancelled if cancelled.any?
        Row.new(order: order, issues: issues, carrier: carrier, duplicate_of: twin, cancelled_count: cancelled.size, cancelled_last_at: cancelled.map { |other| other.cancelled_at || other.created_at }.max)
      end
    end

    def incomplete?(order, key)
      key.length < 9 || order.customer_address.to_s.strip.length < 4 || order.customer_city.to_s.strip.empty?
    end

    # Same lines and quantities, close in time, and still alive; the earlier order of a pair is kept, the later one held back.
    def duplicate?(order, other)
      return false if other.status.in?(%w[cancelled returned])
      return false unless (other.created_at - order.created_at).abs <= DUPLICATE_WINDOW
      return false unless signature(order) == signature(other)

      other.id < order.id || parcel?(other)
    end

    def parcel?(order) = CARRIERS.any? { |carrier| order.public_send("#{carrier}_code").present? }

    # The company that will take this parcel, or nil when none can (not connected, or several connected and none chosen).
    def carrier_for(order)
      chosen = order.delivery_provider.to_s.presence
      return (configured.include?(chosen) ? chosen : nil) if chosen

      configured.one? ? configured.first : nil
    end

    def configured
      @configured ||= Demo::Workspace.demo_store?(store) ? [ "sendit" ] : CARRIERS.select { |carrier| store.public_send("#{carrier}_configured?") }
    end

    def signature(order)
      order.order_items.map { |item| [ item.product_id || item.product_name, item.variant_name.to_s, item.quantity ] }.sort_by(&:to_s)
    end

    # Every order of this store, within the longest window, sharing a phone number with a candidate.
    def related_orders(keys)
      return {} if keys.empty?

      since = @now - [ DUPLICATE_WINDOW, CANCELLED_WINDOW ].max
      store.orders.where(created_at: since..).where("#{PHONE_KEY_SQL} IN (?)", keys).includes(:order_items).group_by { |other| key_for(other.customer_phone) }
    end
  end
end
