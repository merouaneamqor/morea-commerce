# frozen_string_literal: true

# A visitor's request for a workspace. Provisioned after platform approval.
class AccessRequest < ApplicationRecord
  STATUSES = %w[pending approved rejected].freeze
  MAX_PER_IP_PER_HOUR = 5

  belongs_to :store, optional: true
  belongs_to :reviewed_by, class_name: "User", optional: true

  normalizes :email, with: ->(e) { e.strip.downcase }
  normalizes :store_name, with: ->(n) { n.to_s.squish }
  normalizes :phone, with: ->(p) { p.to_s.strip.presence }

  validates :store_name, presence: true, length: { in: 2..80 }
  validates :email, presence: true, length: { maximum: 160 }, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :email, uniqueness: { conditions: -> { pending } }, if: :pending?
  validates :phone, length: { maximum: 30 }, allow_nil: true
  validates :locale, inclusion: { in: Morea::Locales::AVAILABLE.map(&:to_s) }
  validates :status, inclusion: { in: STATUSES }
  validates :storefront_enabled, inclusion: { in: [ true, false ] }

  scope :pending, -> { where(status: "pending") }

  def self.throttled?(ip)
    ip.present? && where(ip: ip).where("created_at > ?", 1.hour.ago).count >= MAX_PER_IP_PER_HOUR
  end

  def pending? = status == "pending"

  def approve!(store:, reviewer:)
    update!(status: "approved", store: store, reviewed_by: reviewer, reviewed_at: Time.current)
  end

  def reject!(reviewer:)
    update!(status: "rejected", reviewed_by: reviewer, reviewed_at: Time.current)
  end
end
