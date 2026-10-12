# frozen_string_literal: true

class OauthClient < ApplicationRecord
  validates :client_id, presence: true, uniqueness: true
  validates :redirect_uris, presence: true

  def self.register!(name:, redirect_uris:)
    uris = Array(redirect_uris).map(&:to_s).uniq
    raise ArgumentError, "redirect_uris required" if uris.empty?
    raise ArgumentError, "redirect_uri not allowed" unless uris.all? { |uri| allowed_redirect?(uri) }

    create!(
      client_id: SecureRandom.uuid,
      client_name: name.to_s.presence || "MCP client",
      redirect_uris: uris
    )
  end

  def self.allowed_redirect?(uri)
    parsed = URI.parse(uri)
    return false if parsed.scheme.blank?
    return false if %w[javascript data file].include?(parsed.scheme.downcase)
    return false if %w[http https].include?(parsed.scheme.downcase) && parsed.host.blank?

    true
  rescue URI::InvalidURIError
    false
  end

  def allows_redirect?(uri)
    redirect_uris.include?(uri.to_s)
  end
end
