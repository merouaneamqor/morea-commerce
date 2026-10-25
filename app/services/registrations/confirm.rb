# frozen_string_literal: true

module Registrations
  class Confirm
    def self.call(token:, password:, password_confirmation:)
      new(token, password, password_confirmation).call
    end

    def initialize(token, password, password_confirmation)
      @token = token.to_s
      @password = password
      @password_confirmation = password_confirmation
    end

    def call
      registration = Registration.find_by_token_for(:email_verification, @token)
      return unless registration

      registration.with_lock do
        # Recheck inside the lock: a simultaneous resend/confirmation invalidates this token.
        current = Registration.find_by_token_for(:email_verification, @token)
        return unless current&.id == registration.id && !registration.verified?
        return if User.exists?(email: registration.email)

        registration.assign_attributes(password: @password, password_confirmation: @password_confirmation)
        return registration unless registration.valid?(:confirmation)

        store = Store.create!(
          name: registration.business_name,
          slug: "#{registration.business_name.parameterize.first(40).presence || 'workspace'}-#{SecureRandom.hex(6)}",
          email: registration.email,
          currency: "MAD",
          storefront_enabled: false,
          subscription_required: true,
          billing_status: "canceled",
          billing_period_ends_on: Date.yesterday
        )
        user = store.users.create!(
          email: registration.email,
          name: registration.business_name,
          password_digest: registration.password_digest,
          admin: true,
          super_admin: false
        )
        registration.update!(user: user, verified_at: Time.current, verification_nonce: SecureRandom.hex(24))
        user
      end
    end
  end
end
