# Releases confirmation claims that saw no activity for 15 minutes, for every store. The desk also does it
# before each action; this keeps the queue honest while nobody is acting.
class ReleaseIdleClaimsJob < ApplicationJob
  queue_as :default

  def perform
    Store.where(id: OrderConfirmation.where.not(assigned_user_id: nil).select(:store_id)).find_each do |store|
      Confirmations::ClaimExpiry.release_idle!(store)
    end
  end
end
