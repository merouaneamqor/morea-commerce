class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("MAIL_FROM") { "no-reply@#{ENV.fetch("APP_BASE_DOMAIN", "localhost")}" }
  layout "mailer"
end
