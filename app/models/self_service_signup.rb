# frozen_string_literal: true

# Step 1 of the seallo signup: creates the seller's workspace and owner account in one go.
# A plan picked before signing up (plans page visited as a guest) is applied here.
class SelfServiceSignup
  include ActiveModel::Model
  include ActiveModel::Attributes

  PHONE_FORMAT = /\A(\+212|0)[5-7]\d{8}\z/

  attribute :name, :string
  attribute :store_name, :string
  attribute :phone, :string
  attribute :email, :string
  attribute :password, :string
  attribute :password_confirmation, :string
  attribute :currency, :string

  attr_reader :user

  # Keeps only digits and a leading "+" so "06 61 22 33 44" is accepted.
  def phone=(value)
    super(value.to_s.gsub(/(?!\A\+)[^\d]/, ""))
  end

  def email=(value)
    super(value.to_s.strip.downcase)
  end

  validates :name, presence: true, length: { maximum: 120 }
  validates :store_name, presence: true, length: { maximum: 120 }
  validates :phone, format: { with: PHONE_FORMAT }
  validates :email, presence: true, length: { maximum: 160 }, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, presence: true
  validates :password_confirmation, presence: true
  validates :password, confirmation: true
  validates :currency, inclusion: { in: ->(_) { Plans.currencies.keys } }, allow_blank: true
  validate :email_available

  # Returns the new owner, or nil with errors on the form.
  def save(plan_choice: nil)
    return unless valid?

    ApplicationRecord.transaction do
      store = Store.create!(
        name: store_name,
        slug: "#{store_name.parameterize.first(40).presence || 'workspace'}-#{SecureRandom.hex(6)}",
        email: email,
        phone: phone,
        currency: currency.presence || plan_choice&.dig("currency") || Plans.reference_currency,
        storefront_enabled: false,
        admin_theme: "seallo",
        subscription_required: true,
        billing_status: "canceled",
        billing_period_ends_on: Date.yesterday
      )
      owner = store.users.new(email: email, name: name, password: password, password_confirmation: password_confirmation, admin: true, super_admin: false)
      unless owner.save
        owner.errors.each { |error| errors.add(error.attribute, error.message) }
        raise ActiveRecord::Rollback
      end

      plan = Plans.plan?(plan_choice&.dig("plan")) ? plan_choice["plan"] : "free"
      billing = Plans::BILLINGS.include?(plan_choice&.dig("billing")) ? plan_choice["billing"] : "monthly"
      store.choose_plan!(plan: plan, billing: billing, currency: store.currency)
      @user = owner
    end
    @user
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    errors.add(:email, :taken)
    nil
  end

  private

  def email_available
    return if email.blank?

    errors.add(:email, :taken) if User.exists?(email: email) || Registration.exists?(email: email)
  end
end
