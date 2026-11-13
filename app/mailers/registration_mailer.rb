# frozen_string_literal: true

class RegistrationMailer < ApplicationMailer
  def verification(registration)
    @registration = registration
    return if @registration.verified?

    I18n.with_locale(@registration.locale) do
      @verification_url = "#{Store.platform_origin}#{Rails.application.routes.url_helpers.signup_verify_path(token: @registration.verification_token, locale: @registration.locale)}"
      mail(to: @registration.email, subject: t("registration_mailer.subject", name: Store.platform_name))
    end
  end
end
