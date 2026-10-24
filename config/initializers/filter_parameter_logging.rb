# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc
]

# Imported customer contacts and confirmation notes must not enter request logs.
Rails.application.config.filter_parameters += [
  "order.name", "order.phone", "order.city", "order.district", "order.address", :notes
]

# External webhook bodies contain customer details at provider-specific paths.
Rails.application.config.filter_parameters += [
  :customer, :shipping_address, :billing_address, :billing, :shipping, :data,
  :line_items, :variants, :phone, :first_name, :last_name, :address1, :address2
]
