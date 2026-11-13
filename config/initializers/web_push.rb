# VAPID keys identify this server to browser push services. Without them, order
# alerts are switched off rather than failing: generate a pair once per environment.
Rails.application.config.x.web_push = {
  public_key: ENV["VAPID_PUBLIC_KEY"].presence,
  private_key: ENV["VAPID_PRIVATE_KEY"].presence,
  subject: ENV.fetch("VAPID_SUBJECT", "mailto:support@example.test")
}.freeze
