# frozen_string_literal: true

module Oauth
  class Codes
    TTL = 10.minutes

    def self.issue(store:, client_id:, redirect_uri:, code_challenge:)
      code = SecureRandom.urlsafe_base64(32)
      Rails.cache.write(
        key(code),
        {
          "store_id" => store.id,
          "client_id" => client_id,
          "redirect_uri" => redirect_uri,
          "code_challenge" => code_challenge
        },
        expires_in: TTL
      )
      code
    end

    def self.take(code)
      return if code.blank?

      payload = Rails.cache.read(key(code))
      Rails.cache.delete(key(code))
      payload
    end

    def self.s256?(verifier, challenge)
      return false if verifier.blank? || challenge.blank?

      digest = Digest::SHA256.digest(verifier)
      encoded = Base64.urlsafe_encode64(digest, padding: false)
      return false unless encoded.bytesize == challenge.bytesize

      ActiveSupport::SecurityUtils.secure_compare(encoded, challenge)
    end

    def self.key(code)
      "oauth:code:#{code}"
    end
  end
end
