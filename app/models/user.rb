class User < ApplicationRecord
  has_secure_password

  # Super admins may be platform-only (no store) or also staff on a home store.
  belongs_to :store, optional: true
  has_many :order_events, dependent: :nullify

  scope :super_admins, -> { where(super_admin: true) }

  validates :email, presence: true
  validates :email, uniqueness: { scope: :store_id }, unless: :platform_only_super_admin?
  validates :email, uniqueness: true, if: :platform_only_super_admin?
  validates :store, presence: true, unless: :super_admin?

  normalizes :email, with: ->(e) { e.strip.downcase }

  def platform_admin?
    super_admin?
  end

  private

  def platform_only_super_admin?
    super_admin? && store_id.blank?
  end
end
