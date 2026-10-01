class Order < ApplicationRecord
  belongs_to :store
  belongs_to :customer
  has_many :order_items, dependent: :destroy
  has_many :inventory_movements, dependent: :nullify

  STATUSES = %w[new confirmed preparing shipped delivered cancelled].freeze
  TRANSITIONS = {
    "new" => %w[confirmed cancelled],
    "confirmed" => %w[preparing cancelled],
    "preparing" => %w[shipped cancelled],
    "shipped" => %w[delivered],
    "delivered" => [],
    "cancelled" => []
  }.freeze

  validates :number, :status, :customer_name, :customer_phone, :customer_city, :customer_address, presence: true
  validates :number, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
  validates :total_cents, numericality: { greater_than_or_equal_to: 0 }

  before_validation :assign_number, on: :create

  scope :recent, -> { order(created_at: :desc) }
  scope :by_status, ->(status) { where(status: status) if status.present? }

  def can_transition_to?(new_status)
    TRANSITIONS.fetch(status, []).include?(new_status.to_s)
  end

  def transition_to!(new_status, reason: nil)
    new_status = new_status.to_s
    raise ArgumentError, "Invalid transition #{status} → #{new_status}" unless can_transition_to?(new_status)

    transaction do
      case new_status
      when "confirmed"
        reserve_inventory!
        self.confirmed_at = Time.current
      when "shipped"
        self.shipped_at = Time.current
      when "delivered"
        self.delivered_at = Time.current
      when "cancelled"
        restore_inventory! if %w[confirmed preparing shipped].include?(status)
        self.cancelled_at = Time.current
        self.cancel_reason = reason
      end

      update!(status: new_status)
    end

    OrderStatusJob.perform_later(id)
    self
  end

  def self.cancel_rate
    total = count
    return 0 if total.zero?

    (by_status("cancelled").count.to_f / total * 100).round(1)
  end

  def status_label
    status.humanize
  end

  def total_display
    "#{(total_cents / 100.0).to_i.to_fs(:delimited)} #{currency}"
  end

  private

  def assign_number
    return if number.present?

    loop do
      self.number = format("M%06d", SecureRandom.random_number(1_000_000))
      break unless Order.exists?(number: number)
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

  def restore_inventory!
    order_items.includes(:product, :product_variant).each do |item|
      target = item.product_variant || item.product
      next unless item.product.track_inventory

      target.update!(stock: target.stock + item.quantity)
      inventory_movements.create!(
        product: item.product,
        product_variant: item.product_variant,
        quantity: item.quantity,
        reason: "order_cancelled",
        note: "Order #{number}"
      )
    end
  end
end
