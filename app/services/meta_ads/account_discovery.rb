# frozen_string_literal: true

module MetaAds
  # Lists the ad accounts the authorizing user can read and caches them for the store. Existing rows keep
  # their selection and sync state. Accounts Meta stops returning are left alone; their sync fails with
  # a permission error and the merchant is asked to reconnect.
  class AccountDiscovery
    FIELDS = %w[id name currency timezone_name].freeze

    def initialize(connection:, transport: nil)
      @connection = connection
      @transport = transport
    end

    def call
      rows = Client.new(connection: @connection, transport: @transport).collect("me/adaccounts", fields: FIELDS).data
      MetaAds::AdAccount.transaction do
        rows.filter_map { |row| upsert(row) }
      end
    end

    private

    def upsert(row)
      id = row["id"].to_s
      return unless id.match?(/\Aact_[0-9]+\z/)

      account = @connection.store.meta_ads_ad_accounts.find_or_initialize_by(meta_ad_account_id: id)
      account.connection = @connection
      account.assign_attributes(name: row["name"].to_s.truncate(255), currency: row["currency"].presence, timezone_name: row["timezone_name"].presence)
      account.save!
      account
    end
  end
end
