# frozen_string_literal: true

class OauthAccessToken < ApplicationRecord
  belongs_to :store

  ACCESS_TTL = 30.days
  REFRESH_TTL = 90.days

  def self.issue!(store:, client_id:)
    access = "morea_oa_#{SecureRandom.urlsafe_base64(32)}"
    refresh = "morea_or_#{SecureRandom.urlsafe_base64(32)}"
    create!(
      store: store,
      client_id: client_id,
      token_digest: Store.digest_api_token(access),
      refresh_digest: Store.digest_api_token(refresh),
      expires_at: ACCESS_TTL.from_now,
      refresh_expires_at: REFRESH_TTL.from_now
    )
    [ access, refresh ]
  end

  def self.authenticate(token)
    return if token.blank?

    grant = find_by(token_digest: Store.digest_api_token(token))
    return if grant.nil? || grant.expires_at.past?

    grant
  end

  def self.rotate!(refresh_token)
    return if refresh_token.blank?

    grant = find_by(refresh_digest: Store.digest_api_token(refresh_token))
    return if grant.nil? || grant.refresh_expires_at.past?

    store = grant.store
    client_id = grant.client_id
    grant.destroy!
    issue!(store: store, client_id: client_id)
  end
end
