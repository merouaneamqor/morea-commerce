# frozen_string_literal: true

# Delivery credentials are supplied by the deployment environment, never saved in code.
# Required for real delivery: SMTP_ADDRESS, SMTP_USERNAME, SMTP_PASSWORD, MAIL_FROM.
# Optional: SMTP_PORT (587), SMTP_DOMAIN (falls back to APP_BASE_DOMAIN), SMTP_AUTHENTICATION (plain).
if ENV["SMTP_ADDRESS"].present?
  Rails.application.config.action_mailer.delivery_method = :smtp
  Rails.application.config.action_mailer.perform_deliveries = true
  Rails.application.config.action_mailer.raise_delivery_errors = true
  Rails.application.config.action_mailer.smtp_settings = {
    address: ENV.fetch("SMTP_ADDRESS"),
    port: ENV.fetch("SMTP_PORT", "587").to_i,
    domain: ENV.fetch("SMTP_DOMAIN") { ENV.fetch("APP_BASE_DOMAIN", "localhost") },
    user_name: ENV["SMTP_USERNAME"],
    password: ENV["SMTP_PASSWORD"],
    authentication: ENV.fetch("SMTP_AUTHENTICATION", "plain"),
    enable_starttls_auto: true,
    openssl_verify_mode: "peer"
  }
elsif Rails.env.production?
  Rails.logger.warn(
    "[mail] SMTP_ADDRESS is unset. Signup and password-reset mail will hit localhost:25 and fail. " \
    "Set MAIL_FROM, SMTP_ADDRESS, SMTP_PORT, SMTP_USERNAME, and SMTP_PASSWORD on morea-web."
  )
end
