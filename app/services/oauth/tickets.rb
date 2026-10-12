# frozen_string_literal: true

module Oauth
  class Tickets
    TTL = 15.minutes

    def self.issue(query)
      id = SecureRandom.urlsafe_base64(18)
      Rails.cache.write(key(id), query.stringify_keys, expires_in: TTL)
      id
    end

    def self.read(id)
      return if id.blank?

      payload = Rails.cache.read(key(id))
      payload.symbolize_keys if payload.present?
    end

    def self.key(id)
      "oauth:ticket:#{id}"
    end
  end
end
