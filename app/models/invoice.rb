# frozen_string_literal: true

class Invoice < ApplicationRecord
  STATUSES = %w[draft issued paid void].freeze

  belongs_to :store

  validates :number, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
  validates :billing_interval, inclusion: { in: Store::BILLING_INTERVALS }
  validates :amount_cents, numericality: { greater_than_or_equal_to: 0 }
  validates :period_starts_on, :period_ends_on, presence: true
  validate :period_end_after_start

  before_validation :assign_number, on: :create
  before_validation :assign_defaults_from_store, on: :create

  scope :overdue, -> { where(status: "issued").where("due_on < ?", Date.current) }
  scope :open_issued, -> { where(status: "issued") }

  def amount_dh
    amount_cents.to_i / 100
  end

  def amount_dh=(value)
    self.amount_cents = value.to_i * 100
  end

  def overdue?
    status == "issued" && due_on.present? && due_on < Date.current
  end

  def issue!
    raise ActiveRecord::RecordInvalid, self unless status == "draft"

    self.status = "issued"
    self.issued_at ||= Time.current
    self.due_on ||= Date.current + 7.days
    save!
    store.sync_billing_past_due!
    self
  end

  def mark_paid!
    raise ActiveRecord::RecordInvalid, self unless status == "issued"

    transaction do
      update!(status: "paid", paid_at: Time.current)
      ends = [ store.billing_period_ends_on, period_ends_on ].compact.max
      store.update!(billing_status: "active", billing_period_ends_on: ends)
    end
    self
  end

  def void!
    raise ActiveRecord::RecordInvalid, self unless status.in?(%w[draft issued])

    update!(status: "void")
    store.sync_billing_past_due!
    self
  end

  def self.next_number(date = Date.current)
    prefix = "INV-#{date.year}-"
    last = where("number LIKE ?", "#{prefix}%").order(:number).maximum(:number)
    seq = last ? last.delete_prefix(prefix).to_i + 1 : 1
    format("%s%04d", prefix, seq)
  end

  def self.build_for_store(store)
    start_on = store.billing_period_ends_on.present? ? store.billing_period_ends_on + 1.day : Date.current
    end_on =
      case store.billing_interval
      when "yearly" then start_on + 1.year - 1.day
      else start_on + 1.month - 1.day
      end

    store.invoices.new(
      amount_cents: store.billing_amount_cents,
      billing_interval: store.billing_interval,
      period_starts_on: start_on,
      period_ends_on: end_on,
      due_on: Date.current + 7.days,
      status: "draft"
    )
  end

  private

  def assign_number
    self.number = self.class.next_number if number.blank?
  end

  def assign_defaults_from_store
    return unless store

    self.billing_interval = store.billing_interval if billing_interval.blank?
  end

  def period_end_after_start
    return if period_starts_on.blank? || period_ends_on.blank?
    return if period_ends_on >= period_starts_on

    errors.add(:period_ends_on, "must be on or after period start")
  end
end
