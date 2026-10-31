class User < ApplicationRecord
  has_secure_password

  generates_token_for :password_reset, expires_in: 15.minutes do
    password_salt&.last(10)
  end

  # Every password that is set or changed, through any flow (staff, tenant admin,
  # platform user, recovery) must meet this policy. Stored hashes cannot be re-checked,
  # so existing passwords stay valid until their owner changes them.
  MIN_PASSWORD_LENGTH = 12
  MAX_PASSWORD_BYTES = 72 # bcrypt ignores anything longer

  validates :password, length: { minimum: MIN_PASSWORD_LENGTH }, allow_nil: true
  validate :password_within_bcrypt_limit, :password_not_derived_from_email, if: -> { password.present? }
  validates :password_confirmation, presence: true, on: :password_reset

  # Super admins may be platform-only (no store) or also staff on a home store.
  belongs_to :store, optional: true
  has_many :order_events, dependent: :nullify
  has_many :confirmation_shifts, dependent: :nullify
  has_many :push_subscriptions, dependent: :destroy

  STATUSES = %w[active suspended archived].freeze
  CONFIRMATION_ROLES = %w[agent supervisor].freeze

  scope :super_admins, -> { where(super_admin: true) }
  scope :active, -> { where(status: "active") }
  scope :with_status, ->(status) { where(status: status) }

  validates :status, inclusion: { in: STATUSES }
  validates :confirmation_role, inclusion: { in: CONFIRMATION_ROLES }
  before_validation :agents_are_not_admins

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
    active? && (admin? || super_admin? || confirmation_agent?)
  end

  def confirmation_agent?
    confirmation_role == "agent"
  end

  # Store admins and confirmation agents of this store may work its desk.
  def can_work_desk_for?(store_id)
    super_admin? || (self.store_id.present? && self.store_id == store_id && (admin? || confirmation_agent?))
  end

  def platform_admin?
    super_admin?
  end

  # Agents work the desk and see only their own figures and claims. Supervisors
  # and store admins keep the team view.
  def confirmation_agent_view?
    confirmation_agent? && !super_admin?
  end

  private

  def password_within_bcrypt_limit
    errors.add(:password, :too_long, count: MAX_PASSWORD_BYTES) if password.bytesize > MAX_PASSWORD_BYTES
  end

  def password_not_derived_from_email
    local_part = email.to_s.split("@").first.to_s.downcase
    errors.add(:password, :contains_email) if local_part.length >= 4 && password.downcase.include?(local_part)
  end

  def platform_only_super_admin?
    super_admin? && store_id.blank?
  end

  def agents_are_not_admins
    self.admin = false if confirmation_agent?
  end
end
