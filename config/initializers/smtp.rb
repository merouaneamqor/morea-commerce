# frozen_string_literal: true

# Delivery credentials are supplied by the deployment environment, never saved in code.
if ENV["SMTP_ADDRESS"].present?
  Rails.application.config.action_mailer.delivery_method = :smtp
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
end
