# frozen_string_literal: true

module MetaAds
  # Replaces the set of ad accounts a store syncs. Only accounts already cached under the store's own
  # connection can be selected; submitted IDs never reach another store's rows.
  class AccountSelection
    class Error < StandardError
      attr_reader :code

      def initialize(code)
        @code = code
        super("Meta ad account selection: #{code}")
      end
    end

    def self.call(connection:, ids:)
      raise Error.new("reauthorization_required") unless connection.active?

      wanted = Array(ids).map(&:to_s).uniq
      accounts = connection.ad_accounts.where(store_id: connection.store_id).to_a
      raise Error.new("unknown_account") unless (wanted - accounts.map(&:meta_ad_account_id)).empty?

      connection.with_lock do
        accounts.each do |account|
          select = wanted.include?(account.meta_ad_account_id)
          next if account.selected == select

          account.update!(selected: select, sync_status: "pending", retry_count: 0, last_error_code: nil, last_error_message: nil,
            next_sync_at: select ? Time.current : nil)
        end
      end
      accounts
    rescue ActiveRecord::RecordNotUnique
      # Another store already syncs this ad account; one Meta ad account is never attached to two stores.
      raise Error.new("already_connected")
    rescue ActiveRecord::RecordInvalid
      raise Error.new("incomplete_account")
    end
  end
end
