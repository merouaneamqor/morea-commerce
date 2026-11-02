module Connections
  # Redeems a one-time authorization code from the Seallo Connect for WooCommerce
  # plugin and returns the connection's delivery URL and a freshly generated
  # signing secret. The secret is returned only here; Morea stores it encrypted.
  class WoocommerceConnect
    class Error < StandardError; end
    Result = Struct.new(:connection, :secret, keyword_init: true)

    SITE_PATTERN = /\A[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)+\z/
    VERIFIER_PATTERN = /\A[A-Za-z0-9\-._~]{43,128}\z/

    def self.call(code:, code_verifier:, site:)
      raise Error, "invalid_code" unless code.to_s.match?(/\A[0-9a-f]{48}\z/)
      raise Error, "invalid_verifier" unless code_verifier.to_s.match?(VERIFIER_PATTERN)
      raise Error, "invalid_site" unless site.is_a?(String) && site.bytesize <= 253 && site.match?(SITE_PATTERN)

      pending = WoocommerceConnectionCode.find_by(digest: Digest::SHA256.hexdigest(code))
      raise Error, "invalid_code" unless pending

      result = nil
      pending.with_lock do
        user = pending.user.reload
        store = pending.store
        unless pending.consumed_at.nil? && pending.expires_at.future? && WoocommerceConnectionCode.authorized?(store: store, user: user) &&
            pending.site_domain == site && challenge_matches?(pending.code_challenge, code_verifier)
          raise Error, "invalid_code"
        end

        secret = SecureRandom.hex(32)
        connection = store.store_connections.find_or_initialize_by(provider: "woocommerce", external_domain: site)
        connection.name = "WooCommerce · #{site}" if connection.new_record?
        # Re-linking rotates the secret, so the next signed delivery must verify the new one.
        connection.assign_attributes(active: true, webhook_secret: secret, verified_at: nil, last_error_code: nil)
        connection.save!
        pending.update!(consumed_at: Time.current)
        result = Result.new(connection: connection, secret: secret)
      end
      result
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      raise Error, "invalid_connection"
    end

    def self.challenge_matches?(challenge, verifier)
      expected = Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)
      expected.bytesize == challenge.to_s.bytesize && ActiveSupport::SecurityUtils.secure_compare(expected, challenge)
    end
    private_class_method :challenge_matches?
  end
end
