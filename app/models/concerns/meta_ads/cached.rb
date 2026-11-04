# frozen_string_literal: true

module MetaAds
  # Shared shape of cached Meta objects. Rows are upserted by (ad_account, meta_id) and never
  # hard-deleted when Meta stops returning them; last_seen_at lets the UI mark them as removed.
  module Cached
    extend ActiveSupport::Concern

    included do
      belongs_to :store
      belongs_to :ad_account, class_name: "MetaAds::AdAccount"
      attr_readonly :store_id, :ad_account_id, :meta_id

      validates :meta_id, presence: true, uniqueness: { scope: :ad_account_id }
      validate :ad_account_in_same_store
    end

    private

    def ad_account_in_same_store
      errors.add(:ad_account, "must belong to the same store") if ad_account && ad_account.store_id != store_id
    end

    def same_store_parent(name)
      parent = public_send(name)
      errors.add(name, "must belong to the same ad account") if parent && (parent.store_id != store_id || parent.ad_account_id != ad_account_id)
    end
  end
end
