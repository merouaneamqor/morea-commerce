class User < ApplicationRecord
  has_secure_password

  generates_token_for :password_reset, expires_in: 15.minutes do
    password_salt&.last(10)
  end

  # Existing staff passwords remain valid; stronger requirements apply to recovery.
  validates :password, length: { minimum: 12 }, on: :password_reset
  validates :password_confirmation, presence: true, on: :password_reset

  # Super admins may be platform-only (no store) or also staff on a home store.
  belongs_to :store, optional: true
  has_many :order_events, dependent: :nullify

  STATUSES = %w[active suspended archived].freeze

  scope :super_admins, -> { where(super_admin: true) }
  scope :active, -> { where(status: "active") }
  scope :with_status, ->(status) { where(status: status) }

  validates :status, inclusion: { in: STATUSES }

  validates :email, presence: true
  validates :email, uniqueness: { scope: :store_id }, unless: :platform_only_super_admin?
  validates :email, uniqueness: true, if: :platform_only_super_admin?
  validates :store, presence: true, unless: :super_admin?

  normalizes :email, with: ->(e) { e.strip.downcase }

  STATUSES.each do |name|
    define_method(:"#{name}?") { status == name }
  end

  # Only active accounts may authenticate or keep an existing session.
  def can_sign_in?
    active? && (admin? || super_admin?)
  end

  def platform_admin?
    super_admin?
  end

  private

  def platform_only_super_admin?
    super_admin? && store_id.blank?
  end
end
