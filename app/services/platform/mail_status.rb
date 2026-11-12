# frozen_string_literal: true

module Platform
  # Read-only view of outbound mail configuration for platform ops.
  # Never returns secret values, only which required keys are present.
  class MailStatus
    REQUIRED = %w[MAIL_FROM SMTP_ADDRESS SMTP_USERNAME SMTP_PASSWORD].freeze
    OPTIONAL = %w[SMTP_PORT SMTP_DOMAIN SMTP_AUTHENTICATION].freeze

    Result = Struct.new(
      :configured, :missing, :address, :port, :from, :domain, :authentication,
      keyword_init: true
    )

    def self.current
      missing = REQUIRED.select { |key| ENV[key].to_s.strip.empty? }
      Result.new(
        configured: missing.empty?,
        missing: missing,
        address: ENV["SMTP_ADDRESS"].presence,
        port: ENV.fetch("SMTP_PORT", "587"),
        from: ENV["MAIL_FROM"].presence || "no-reply@#{ENV.fetch("APP_BASE_DOMAIN", "localhost")}",
        domain: ENV["SMTP_DOMAIN"].presence || ENV["APP_BASE_DOMAIN"].presence,
        authentication: ENV.fetch("SMTP_AUTHENTICATION", "plain")
      )
    end
  end
end
