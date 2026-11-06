# frozen_string_literal: true

class PlatformPrivacyRightsRequest < ApplicationRecord
  TYPES = PrivacyRightsRequest::TYPES
  STATUSES = PrivacyRightsRequest::STATUSES

  validates :request_type, inclusion: { in: TYPES }
  validates :status, inclusion: { in: STATUSES }
  validates :requester_name, :requester_contact, presence: true
  validates :requester_name, length: { maximum: 120 }
  validates :requester_contact, length: { maximum: 200 }
  validates :details, length: { maximum: 2_000 }, allow_blank: true
  validates :shop_domain, length: { maximum: 255 }, allow_blank: true

  def resolve!
    update!(status: "resolved", resolved_at: Time.current)
  end
end
