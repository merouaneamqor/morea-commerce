# frozen_string_literal: true

module Webhooks
  # Meta's "data deletion request callback": POST of a signed_request. Verified with the app secret (never trusted
  # otherwise), then the user's Meta tokens are removed. Answers with the JSON Meta expects: a URL where the
  # user can check the request and a confirmation code.
  class MetaDataDeletionController < ActionController::API
    wrap_parameters false

    def create
      meta_user_id = MetaAds::DataDeletion.verify!(params[:signed_request])
      deletion = MetaAds::DataDeletion.call(meta_user_id: meta_user_id)
      render json: { url: "#{Store.platform_origin}/auth/meta/data-deletion/#{deletion.confirmation_code}", confirmation_code: deletion.confirmation_code }
    rescue MetaAds::DataDeletion::InvalidRequest
      render json: { error: "invalid_signed_request" }, status: :bad_request
    end
  end
end
