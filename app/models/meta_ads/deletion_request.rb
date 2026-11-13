# frozen_string_literal: true

module MetaAds
  # Receipt of a Meta data deletion request. Shown on the status page under its confirmation code.
  class DeletionRequest < ApplicationRecord
    STATUSES = %w[pending completed].freeze

    validates :confirmation_code, presence: true, uniqueness: true
    validates :meta_user_digest, presence: true
    validates :status, inclusion: { in: STATUSES }
  end
end
