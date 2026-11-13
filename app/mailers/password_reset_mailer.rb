# frozen_string_literal: true

class PasswordResetMailer < ApplicationMailer
  def instructions(user, locale)
    @user = user
    return unless @user.can_sign_in?

    I18n.with_locale(locale) do
      @reset_url = "#{Store.platform_origin}#{Rails.application.routes.url_helpers.edit_password_reset_path(token: @user.generate_token_for(:password_reset), locale: locale)}"
      mail(to: @user.email, subject: t("password_reset_mailer.subject", name: Store.platform_name))
    end
  end
end
