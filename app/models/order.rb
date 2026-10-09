class Order < ApplicationRecord
  belongs_to :store
  belongs_to :customer
  has_many :order_items, dependent: :destroy
  has_many :inventory_movements, dependent: :nullify
  has_many :order_events, dependent: :destroy

  # Happy-path progression (Sendit advances through these)
  FLOW = %w[
    new confirmed preparing awaiting_pickup picked_up in_transit out_for_delivery delivered
  ].freeze

  # Lateral delivery issues (still in flight, stock stays reserved)
  PROBLEM_STATUSES = %w[address_issue unreachable postponed].freeze

  # When Sendit is configured, only the courier API may set these
  SENDIT_OWNED_STATUSES = (
    FLOW - %w[new confirmed] + PROBLEM_STATUSES + %w[returned]
  ).freeze

  STATUSES = (FLOW + PROBLEM_STATUSES + %w[cancelled returned]).freeze

  EDITABLE_STATUSES = %w[new confirmed preparing address_issue].freeze

  RESERVED_STATUSES = (
    FLOW - %w[new delivered] + PROBLEM_STATUSES
  ).freeze

  # Where a problem status re-enters the happy path when Sendit moves forward again
  PROBLEM_RESUME = {
    "address_issue" => "preparing",
    "unreachable" => "out_for_delivery",
    "postponed" => "out_for_delivery"
  }.freeze

  STATUS_LABELS = {
    "new" => "New",
    "confirmed" => "Confirmed",
    "preparing" => "Preparing",
    "awaiting_pickup" => "Awaiting pickup",
    "picked_up" => "Picked up",
    "in_transit" => "In transit",
    "out_for_delivery" => "Out for delivery",
    "unreachable" => "Unreachable",
    "postponed" => "Postponed",
    "address_issue" => "Address issue",
    "delivered" => "Delivered",
    "cancelled" => "Cancelled",
    "returned" => "Returned"
  }.freeze

  TRANSITIONS = {
    "new" => %w[confirmed cancelled],
    "confirmed" => %w[preparing cancelled],
    "preparing" => %w[awaiting_pickup address_issue cancelled],
    "awaiting_pickup" => %w[picked_up address_issue cancelled],
    "picked_up" => %w[in_transit unreachable postponed returned],
    "in_transit" => %w[out_for_delivery unreachable postponed returned],
    "out_for_delivery" => %w[delivered unreachable postponed returned],
    "unreachable" => %w[out_for_delivery postponed returned],
    "postponed" => %w[out_for_delivery unreachable returned],
    "address_issue" => %w[preparing awaiting_pickup cancelled],
    "delivered" => [],
    "cancelled" => [],
    "returned" => []
  }.freeze

  validates :number, :status, :customer_name, :customer_phone, :customer_city, :customer_address, presence: true
  validates :number, uniqueness: { scope: :store_id }
  validates :sendit_code, uniqueness: { scope: :store_id }, allow_nil: true
  validates :status, inclusion: { in: STATUSES }
  validates :total_cents, numericality: { greater_than_or_equal_to: 0 }

  before_validation :assign_number, on: :create

  scope :recent, -> { order(created_at: :desc) }
  scope :by_status, ->(status) { where(status: status) if status.present? }
  scope :active, -> { where(archived_at: nil) }
  scope :archived, -> { where.not(archived_at: nil) }

  # Street address with the quartier, as the courier needs it
  def delivery_address
    [ customer_address, customer_district ].compact_blank.join(", ")
  end

  def archived?
    archived_at.present?
  end

  def tag_list
    tags.to_s.split(",").map(&:strip).compact_blank
  end

  def tag_list=(value)
    list = case value
    when Array then value
    else value.to_s.split(",")
    end
    self.tags = list.map { |t| t.to_s.strip.downcase }.compact_blank.uniq.join(", ").presence
  end

  # Full commercial edit while unshipped and any Sendit parcel can still be changed
  def editable?
    return false unless EDITABLE_STATUSES.include?(status)
    return true if sendit_code.blank?

    Sendit::Sync.new(self).cancellable?
  end

  def edit_lock_reason
    return if editable?
    return "Cancelled orders cannot be edited." if status == "cancelled"
    return "Returned orders cannot be edited." if status == "returned"
    return "Delivered orders cannot be edited." if status == "delivered"
    return "Fix the address, then Save — or wait for Sendit." if status == "address_issue" && sendit_code.present? && !Sendit::Sync.new(self).cancellable?
    return "This parcel is already with the courier." if RESERVED_STATUSES.include?(status) && !EDITABLE_STATUSES.include?(status)
    return "This Sendit parcel has already left the warehouse." if sendit_code.present?

    "This order cannot be edited."
  end

  def inventory_reserved?
    RESERVED_STATUSES.include?(status)
  end

  def archive!(user: nil)
    return self if archived?

    update!(archived_at: Time.current)
    record_event!("archived", body: "Order archived", user: user)
    self
  end

  def unarchive!(user: nil)
    return self unless archived?

    update!(archived_at: nil)
    record_event!("unarchived", body: "Order unarchived", user: user)
    self
  end

  def record_event!(kind, body:, user: nil)
    order_events.create!(kind: kind, body: body, user: user)
  end

  def can_transition_to?(new_status)
    TRANSITIONS.fetch(status, []).include?(new_status.to_s)
  end

  # Buttons staff may click. With Sendit on, delivery states are not listed.
  def staff_transitions
    allowed = TRANSITIONS.fetch(status, [])
    return allowed unless store.sendit_configured?

    allowed.reject { |s| SENDIT_OWNED_STATUSES.include?(s) }
  end

  def sendit_owns_status?(new_status)
    store.sendit_configured? && SENDIT_OWNED_STATUSES.include?(new_status.to_s)
  end

  def transition_to!(new_status, reason: nil, user: nil, source: :staff)
    new_status = new_status.to_s
    if source == :staff && sendit_owns_status?(new_status)
      raise ArgumentError, "“#{STATUS_LABELS.fetch(new_status, new_status.humanize)}” is set by Sendit only. Use Refresh Sendit."
    end
    raise ArgumentError, "Invalid transition #{status} → #{new_status}" unless can_transition_to?(new_status)

    apply_status_change!(new_status, reason: reason, user: user)
  end

  # Step forward through FLOW until `target` (never backwards). Used by Sendit sync.
  def advance_to!(target)
    target = target.to_s
    return self if status == target
    return self unless FLOW.include?(target)

    resume_from_problem_status!(target)

    return self unless FLOW.include?(status)

    while FLOW.index(status) < FLOW.index(target)
      next_status = FLOW[FLOW.index(status) + 1]
      break unless can_transition_to?(next_status)

      transition_to!(next_status, source: :sendit)
    end
    self
  end

  # Sendit may jump to a problem status from several in-flight states
  def move_to_status!(target, reason: nil, user: nil)
    target = target.to_s
    return self if status == target
    raise ArgumentError, "Unknown status #{target}" unless STATUSES.include?(target)

    if PROBLEM_STATUSES.include?(target)
      ensure_ready_for_problem!(target)
      return self if status == target

      apply_status_change!(target, reason: reason, user: user, force: true)
    elsif FLOW.include?(target)
      advance_to!(target)
    elsif can_transition_to?(target)
      transition_to!(target, reason: reason, user: user, source: :sendit)
    elsif target == "returned"
      # Refuse after pickup: force return even if the graph edge is missing
      apply_status_change!(target, reason: reason, user: user, force: true)
    end
    self
  end

  def sendit_label
    Sendit::Sync.label(sendit_status) if sendit_status.present?
  end

  def self.cancel_rate
    total = count
    return 0 if total.zero?

    (by_status("cancelled").count.to_f / total * 100).round(1)
  end

  def status_label
    STATUS_LABELS.fetch(status, status.humanize)
  end

  def total_display
    "#{(total_cents / 100.0).to_i.to_fs(:delimited)} #{currency}"
  end

  private

  def apply_status_change!(new_status, reason: nil, user: nil, force: false)
    raise ArgumentError, "Invalid transition #{status} → #{new_status}" unless force || can_transition_to?(new_status)

    from = status
    transaction do
      case new_status
      when "confirmed"
        reserve_inventory!
        self.confirmed_at = Time.current
      when "picked_up", "in_transit"
        self.shipped_at ||= Time.current
      when "delivered"
        self.delivered_at = Time.current
      when "cancelled"
        restore_inventory! if inventory_reserved? || RESERVED_STATUSES.include?(from)
        self.cancelled_at = Time.current
        self.cancel_reason = reason
      when "returned"
        restore_inventory!(reason: "order_returned") if inventory_reserved? || RESERVED_STATUSES.include?(from) || from == "delivered"
        self.returned_at = Time.current
        self.cancel_reason = reason
      end

      update!(status: new_status)
      body = "Status changed from #{STATUS_LABELS.fetch(from, from.humanize)} to #{STATUS_LABELS.fetch(new_status, new_status.humanize)}"
      body = "#{body} — #{reason}" if reason.present?
      record_event!("status", body: body, user: user)
    end

    OrderStatusJob.perform_later(id)
    enqueue_sendit_sync(new_status)
    self
  end

  def resume_from_problem_status!(target)
    return unless PROBLEM_STATUSES.include?(status)

    resume = PROBLEM_RESUME.fetch(status)
    return unless FLOW.index(resume) && FLOW.index(resume) <= FLOW.index(target)

    update_columns(status: resume, updated_at: Time.current)
    reload
  end

  def ensure_ready_for_problem!(target)
    case target
    when "address_issue"
      advance_to!("preparing") if FLOW.include?(status) && FLOW.index(status) < FLOW.index("preparing")
    when "unreachable", "postponed"
      advance_to!("picked_up") if FLOW.include?(status) && FLOW.index(status) < FLOW.index("picked_up")
    end
  end

  def enqueue_sendit_sync(new_status)
    return unless store.sendit_configured?

    if new_status == "confirmed" && sendit_code.blank?
      SenditSyncJob.perform_later(id, "push")
    elsif new_status == "cancelled" && sendit_code.present? && Sendit::Sync.normalize_status(sendit_status) != "CANCELED"
      # Local cancel first; delete the Sendit parcel right after
      Sendit::Sync.new(self).cancel!
    end
  end

  def assign_number
    return if number.present?

    loop do
      self.number = format("M%06d", SecureRandom.random_number(1_000_000))
      break unless store.orders.exists?(number: number)
    end
  end

  def reserve_inventory!
    order_items.includes(:product, :product_variant).each do |item|
      target = item.product_variant || item.product
      next unless item.product.track_inventory

      if target.stock < item.quantity
        raise StandardError, "Insufficient stock for #{item.product_name}"
      end

      target.update!(stock: target.stock - item.quantity)
      inventory_movements.create!(
        product: item.product,
        product_variant: item.product_variant,
        quantity: -item.quantity,
        reason: "order_confirmed",
        note: "Order #{number}"
      )
    end
  end

  def restore_inventory!(reason: "order_cancelled")
    order_items.includes(:product, :product_variant).each do |item|
      target = item.product_variant || item.product
      next unless item.product.track_inventory

      target.update!(stock: target.stock + item.quantity)
      inventory_movements.create!(
        product: item.product,
        product_variant: item.product_variant,
        quantity: item.quantity,
        reason: reason,
        note: "Order #{number}"
      )
    end
  end
end
