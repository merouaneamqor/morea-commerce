# frozen_string_literal: true

module Platform
  # Returns a workspace to the state it had when it was provisioned: every
  # order, customer, product, page, connection and setting is removed, then the
  # default online store is reinstalled when the storefront is enabled.
  #
  # Kept: the workspace itself (id, slug, name, contact, currency, storefront
  # switch), its billing and invoices, its users, and the audit trail.
  # Nothing is sent to Shopify, WooCommerce, YouCan, Sendit or Meta: connections
  # are forgotten locally and any external webhook keeps pointing at the old token.
  class StoreReset
    # Tables with a store_id that this service empties. A spec fails when a new
    # store-owned table appears in neither list, so every migration has to decide.
    CLEARED_TABLES = %w[
      advertising_accounts agent_changesets agent_payments carts collections confirmation_attempts
      confirmation_shifts customers delivery_accounts discounts home_sections menu_items meta_ads_ad_accounts
      meta_ads_ad_sets meta_ads_ads meta_ads_campaigns meta_ads_connections meta_ads_daily_insights
      oauth_access_tokens order_confirmations order_imports orders pages products push_subscriptions
      seallo_connection_codes store_connections store_expenses store_translations storefront_themes
      woocommerce_connection_codes
    ].freeze
    KEPT_TABLES = %w[access_requests admin_sessions audit_events invoices payments users].freeze

    # Settings put back to the column default. Identity (name, slug, email, phone,
    # currency, storefront switch), billing and the platform's feature flag stay.
    RESET_SETTINGS = %w[
      tagline about whatsapp cod_label cod_note featured_product_id featured_collection_id
      campaign_title campaign_season campaign_image_url campaign_cta sendit_pickup_district_id
      shipping_cents free_shipping_threshold_cents sendit_allow_open sendit_allow_try low_stock_threshold
      meta_pixel_id tiktok_pixel_id sendit_public_key sendit_secret_key sendit_webhook_secret
      discord_orders_webhook_url legal_entity_name cndp_authorization privacy_rights_contact
      api_token_digest api_token_last_four agent_profile admin_theme
    ].freeze

    class Denied < StandardError
      attr_reader :reason

      def initialize(reason)
        @reason = reason
        super(reason.to_s)
      end
    end

    def initialize(store:, actor:, ip: nil)
      @store = store
      @actor = actor
      @ip = ip
    end

    # The caller must echo the workspace slug, so a stray request cannot wipe a store.
    def call(confirmation:)
      raise Denied, :not_super_admin unless @actor&.super_admin?
      raise Denied, :confirmation_mismatch unless confirmation.to_s.strip.casecmp?(@store.slug)

      Store.transaction do
        @store.lock!
        counts = snapshot_counts
        clear_orders
        clear_customers
        clear_catalog
        clear_content
        clear_integrations
        clear_operations
        reset_settings
        @store.install_online_store_defaults! if @store.storefront_enabled?
        record_audit(counts)
      end
      @store
    end

    private

    def snapshot_counts
      { orders: orders.count, customers: customers.count, products: @store.products.count,
        collections: @store.collections.count, pages: @store.pages.count, connections: @store.store_connections.count }
    end

    def orders
      Order.where(store_id: @store.id)
    end

    def customers
      Customer.where(store_id: @store.id)
    end

    def carts
      Cart.where(store_id: @store.id)
    end

    def connections
      StoreConnection.where(store_id: @store.id)
    end

    def clear_orders
      ConfirmationAttempt.where(store_id: @store.id).delete_all
      OrderConfirmation.where(store_id: @store.id).delete_all
      OrderImport.where(store_id: @store.id).delete_all
      ExternalOrderReceipt.where(order_id: orders.select(:id)).or(ExternalOrderReceipt.where(store_connection_id: connections.select(:id))).delete_all
      InventoryMovement.where(order_id: orders.select(:id)).or(InventoryMovement.where(product_id: Product.where(store_id: @store.id).select(:id))).delete_all
      OrderEvent.where(order_id: orders.select(:id)).delete_all
      OrderItem.where(order_id: orders.select(:id)).delete_all
      orders.delete_all
    end

    def clear_customers
      CartItem.where(cart_id: carts.select(:id)).delete_all
      carts.delete_all
      Address.where(customer_id: customers.select(:id)).delete_all
      customers.delete_all
    end

    # Records with uploaded images go through destroy so Active Storage purges the files.
    def clear_catalog
      @store.products.find_each(&:destroy!)
      @store.collections.find_each(&:destroy!)
      @store.discounts.delete_all
    end

    def clear_content
      @store.pages.find_each(&:destroy!)
      @store.home_sections.find_each(&:destroy!)
      @store.menu_items.find_each(&:destroy!)
      StorefrontTheme.where(store_id: @store.id).delete_all
      StoreTranslation.where(store_id: @store.id).delete_all
    end

    def clear_integrations
      # Shopify privacy requests are compliance records: detach them from the connection
      # being removed (the foreign key has no ON DELETE rule) instead of deleting them.
      ShopifyPrivacyRequest.where(store_connection_id: connections.select(:id)).update_all(store_connection_id: nil)
      connections.delete_all
      SealloConnectionCode.where(store_id: @store.id).delete_all
      WoocommerceConnectionCode.where(store_id: @store.id).delete_all
      clear_meta_ads
      campaigns = AdvertisingCampaign.where(advertising_account_id: AdvertisingAccount.where(store_id: @store.id).select(:id))
      AdvertisingPerformance.where(advertising_campaign_id: campaigns.select(:id)).delete_all
      campaigns.delete_all
      AdvertisingAccount.where(store_id: @store.id).delete_all
      OauthAccessToken.where(store_id: @store.id).delete_all
      AgentChangeset.where(store_id: @store.id).delete_all
    end

    # No models exist for these tables, so they are cleared child-first in SQL.
    def clear_meta_ads
      %w[meta_ads_daily_insights meta_ads_ads meta_ads_ad_sets meta_ads_campaigns meta_ads_ad_accounts meta_ads_connections].each do |table|
        next unless ActiveRecord::Base.connection.table_exists?(table)

        ActiveRecord::Base.connection.delete(ActiveRecord::Base.sanitize_sql([ "DELETE FROM #{table} WHERE store_id = ?", @store.id ]))
      end
    end

    def clear_operations
      AgentPayment.where(store_id: @store.id).delete_all
      ConfirmationShift.where(store_id: @store.id).delete_all
      PushSubscription.where(store_id: @store.id).delete_all
      StoreExpense.where(store_id: @store.id).delete_all
    end

    # Columns are written directly: the translated setters (tagline, cod_label, ...)
    # would build a default-locale translation row a new workspace does not have.
    def reset_settings
      defaults = RESET_SETTINGS.index_with { |attribute| Store.column_defaults[attribute] }
      @store.update_columns(defaults.merge(updated_at: Time.current))
      @store.reload
    end

    def record_audit(counts)
      AuditEvent.create!(
        store: @store, actor_user: @actor, actor_label: @actor.email.to_s.first(80), source: "ui",
        acting_as_platform: true, action: "store.reset", subject: @store, ip: @ip.to_s.first(64).presence,
        metadata: counts.merge(slug: @store.slug)
      )
    end
  end
end
