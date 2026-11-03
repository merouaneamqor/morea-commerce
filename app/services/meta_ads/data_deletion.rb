# frozen_string_literal: true

require "base64"
require "openssl"

module MetaAds
  # Meta's data deletion callback: verifies the signed_request with the app secret, removes the user's Meta tokens
  # (every connection of that Meta user, in any store) and records a confirmation code for the status page.
  # The Meta user id itself is kept only as a SHA-256 digest. Spend already synced stays with the merchant's records.
  class DataDeletion
    class InvalidRequest < StandardError; end

    # Returns the Meta user id of a valid signed_request. Anything else raises InvalidRequest.
    def self.verify!(signed_request)
      secret = Config.app_secret
      raise InvalidRequest unless secret.present? && signed_request.is_a?(String) && signed_request.bytesize < 4096

      signature, payload = signed_request.split(".", 2)
      raise InvalidRequest if signature.blank? || payload.blank?

      expected = OpenSSL::HMAC.digest("SHA256", secret, payload)
      raise InvalidRequest unless ActiveSupport::SecurityUtils.secure_compare(expected, decode(signature))

      data = JSON.parse(decode(payload))
      raise InvalidRequest unless data.is_a?(Hash) && data["algorithm"].to_s.upcase == "HMAC-SHA256" && data["user_id"].to_s.match?(/\A\d{1,30}\z/)

      data["user_id"].to_s
    rescue JSON::ParserError, ArgumentError
      raise InvalidRequest
    end

    def self.call(meta_user_id:)
      removed = 0
      MetaAds::Connection.where(meta_user_id: meta_user_id).find_each do |connection|
        connection.with_lock do
          connection.update!(status: "disconnected", access_token: nil, token_expires_at: nil, meta_user_id: nil, granted_scopes: [],
            oauth_state_digest: nil, oauth_state_expires_at: nil, last_error_code: nil)
          connection.ad_accounts.update_all(selected: false, sync_status: "pending", next_sync_at: nil)
        end
        removed += 1
      end
      MetaAds::DeletionRequest.create!(confirmation_code: SecureRandom.hex(12), meta_user_digest: Digest::SHA256.hexdigest(meta_user_id),
        status: "completed", connections_removed: removed)
    end

    def self.decode(value)
      Base64.urlsafe_decode64(value.to_s.ljust((value.to_s.length + 3) / 4 * 4, "="))
    end
    private_class_method :decode
  end
end
