# frozen_string_literal: true

# Public Seallo Connect pages on the platform apex (overview and support, privacy policy, terms).
# The Shopify app listing links here. Contact details come from the environment so no address is
# invented in source; when none is configured the pages simply omit the email line.
class SealloConnectPagesController < ApplicationController
  layout "bare"

  helper_method :support_email

  def show; end

  def privacy; end

  def terms; end

  private

  def support_email
    email = ENV["SEALLO_SUPPORT_EMAIL"].to_s.strip
    email if email.match?(URI::MailTo::EMAIL_REGEXP)
  end
end
