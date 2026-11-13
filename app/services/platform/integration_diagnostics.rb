# frozen_string_literal: true

module Platform
  # Read-only cross-provider connection health for platform support.
  # Never loads tokens, secrets, digests or raw provider payloads.
  class IntegrationDiagnostics
    STORE_CONNECTION_COLUMNS = %i[
      id store_id provider name external_domain active verified_at last_received_at
      last_error_code shopify_oauth shopify_app shopify_api_verified_at shopify_api_error_code
      shopify_orders_synced_at shopify_sync_state shopify_sync_error updated_at
    ].freeze

    META_COLUMNS = %i[
      id store_id status last_verified_at last_error_code token_expires_at updated_at
    ].freeze

    SENDIT_COLUMNS = %i[
      id store_id provider name code is_active connected_at cities_synced_at updated_at
    ].freeze

    Entry = Struct.new(
      :kind, :provider, :id, :label, :connection_state, :verified_at, :last_sync_at,
      :error_code, :failing, :store_id, :store_name, :store_slug, keyword_init: true
    ) do
      def failing?
        failing
      end

      def recheckable?
        kind.present? && id.present?
      end
    end

    Workspace = Struct.new(:store, :entries, keyword_init: true) do
      def failing_entries
        entries.select(&:failing?)
      end

      def failing?
        failing_entries.any?
      end
    end

    LIST_LIMIT = 100

    def initialize(actor:)
      @actor = actor
    end

    def failing_entries(limit: LIST_LIMIT)
      authorize!
      entries_for_scope(failing_only: true).first(limit)
    end

    def workspaces(limit: LIST_LIMIT)
      authorize!
      stores = connected_stores.limit(limit).to_a
      entries_by_store = entries_for_stores(stores.map(&:id)).group_by(&:store_id)
      stores.map { |store| Workspace.new(store: store, entries: entries_by_store[store.id] || []) }
    end

    def workspace(store)
      authorize!
      raise ActiveRecord::RecordNotFound unless store.is_a?(Store) && store.persisted?

      store = Store.select(:id, :name, :slug, :sendit_public_key, :sendit_secret_key).find(store.id)
      Workspace.new(store: store, entries: entries_for_stores([ store.id ]))
    end

    private

    def authorize!
      raise ActiveRecord::RecordNotFound unless @actor.is_a?(User) && @actor.persisted?
      @actor.reload
      raise ActiveRecord::RecordNotFound unless @actor.active? && @actor.super_admin?
    end

    def connected_stores
      ids = StoreConnection.distinct.pluck(:store_id) +
        MetaAds::Connection.distinct.pluck(:store_id) +
        DeliveryAccount.where(provider: "sendit").distinct.pluck(:store_id) +
        Store.where.not(sendit_public_key: [ nil, "" ]).where.not(sendit_secret_key: [ nil, "" ]).pluck(:id)
      Store.where(id: ids.uniq).select(:id, :name, :slug, :sendit_public_key, :sendit_secret_key).order(:name, :id)
    end

    def entries_for_scope(failing_only:)
      store_ids = connected_stores.limit(LIST_LIMIT).pluck(:id)
      entries = entries_for_stores(store_ids)
      failing_only ? entries.select(&:failing?) : entries
    end

    def entries_for_stores(store_ids)
      return [] if store_ids.blank?

      stores = Store.where(id: store_ids).select(:id, :name, :slug, :sendit_public_key, :sendit_secret_key).index_by(&:id)
      rows = store_connection_entries(store_ids, stores) +
        meta_ads_entries(store_ids, stores) +
        sendit_account_entries(store_ids, stores) +
        legacy_sendit_entries(store_ids, stores)
      rows.sort_by { |entry| [ entry.store_name.to_s.downcase, entry.provider.to_s, entry.id.to_i ] }
    end

    def store_connection_entries(store_ids, stores)
      StoreConnection.where(store_id: store_ids).select(*STORE_CONNECTION_COLUMNS).map do |connection|
        store = stores[connection.store_id]
        state = connection.connection_state
        error = safe_error_code(connection.shopify_api_error_code.presence || connection.last_error_code)
        verified = connection.shopify_oauth? ? connection.shopify_api_verified_at : connection.verified_at
        last_sync = connection.shopify_oauth? ? connection.shopify_orders_synced_at : connection.last_received_at
        failing = connection.active? && (error.present? || connection.shopify_sync_error.present?)
        Entry.new(
          kind: "store_connection",
          provider: connection.provider,
          id: connection.id,
          label: connection.external_domain,
          connection_state: state,
          verified_at: verified,
          last_sync_at: last_sync,
          error_code: error.presence || (connection.shopify_sync_error.present? ? "sync_attention" : nil),
          failing: failing,
          store_id: store&.id,
          store_name: store&.name,
          store_slug: store&.slug
        )
      end
    end

    def meta_ads_entries(store_ids, stores)
      MetaAds::Connection.where(store_id: store_ids).select(*META_COLUMNS).map do |connection|
        store = stores[connection.store_id]
        state = if connection.status == "disconnected"
          "disconnected"
        elsif connection.needs_reconnect?
          "needs_reauthorization"
        elsif connection.last_verified_at.present?
          "verified"
        else
          "configured"
        end
        error = safe_error_code(connection.last_error_code)
        failing = connection.status == "needs_reauthorization" ||
          (connection.active? && (connection.token_expired? || error.present?))
        Entry.new(
          kind: "meta_ads",
          provider: "meta_ads",
          id: connection.id,
          label: "Meta Ads",
          connection_state: state,
          verified_at: connection.last_verified_at,
          last_sync_at: connection.last_verified_at,
          error_code: error,
          failing: failing,
          store_id: store&.id,
          store_name: store&.name,
          store_slug: store&.slug
        )
      end
    end

    def sendit_account_entries(store_ids, stores)
      DeliveryAccount.where(store_id: store_ids, provider: "sendit").select(*SENDIT_COLUMNS).map do |account|
        store = stores[account.store_id]
        state = if !account.is_active?
          "disconnected"
        elsif account.connected_at.present?
          "verified"
        else
          "configured"
        end
        failing = account.is_active? && account.connected_at.blank?
        Entry.new(
          kind: "sendit",
          provider: "sendit",
          id: account.id,
          label: account.name.presence || account.code,
          connection_state: state,
          verified_at: account.connected_at,
          last_sync_at: account.cities_synced_at,
          error_code: failing ? "credentials_unverified" : nil,
          failing: failing,
          store_id: store&.id,
          store_name: store&.name,
          store_slug: store&.slug
        )
      end
    end

    def legacy_sendit_entries(store_ids, stores)
      managed = DeliveryAccount.where(store_id: store_ids, provider: "sendit").distinct.pluck(:store_id)
      store_ids.filter_map do |store_id|
        store = stores[store_id]
        next unless store
        next if managed.include?(store.id)
        # Read legacy columns only; never decrypt DeliveryAccount credentials here.
        next unless store[:sendit_public_key].present? && store[:sendit_secret_key].present?

        Entry.new(
          kind: "sendit_legacy",
          provider: "sendit",
          id: store.id,
          label: "Sendit (legacy)",
          connection_state: "configured",
          verified_at: nil,
          last_sync_at: nil,
          error_code: nil,
          failing: false,
          store_id: store.id,
          store_name: store.name,
          store_slug: store.slug
        )
      end
    end

    SAFE_ERROR_CODES = (
      StoreConnection::SHOPIFY_API_ERRORS +
      %w[incomplete_payload sync_attention credentials_unverified invalid_token permission_denied rate_limited unavailable invalid_response] +
      %w[invalid_keys blocked network unexpected rejected]
    ).freeze

    def safe_error_code(code)
      value = code.to_s
      return if value.blank?
      return value if SAFE_ERROR_CODES.include?(value)
      return value if value.match?(/\A[a-z0-9_]{1,40}\z/)

      "invalid_response"
    end
  end
end
