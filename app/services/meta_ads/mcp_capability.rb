# frozen_string_literal: true

module MetaAds
  # Whether a store connection can call Meta's Ads MCP with the scopes Meta documents.
  module McpCapability
    MCP_SCOPES = %w[ads_mcp_management].freeze
    READ_SCOPES = %w[ads_read ads_management].freeze

    module_function

    def sync_via_mcp?
      ActiveModel::Type::Boolean.new.cast(ENV["META_ADS_SYNC_VIA_MCP"])
    end

    def ready?(connection)
      return false unless connection.is_a?(Connection) && connection.active? && !connection.token_expired?

      scopes = Array(connection.granted_scopes).map(&:to_s)
      (MCP_SCOPES - scopes).empty? && scopes.intersect?(READ_SCOPES)
    end

    def missing_scopes(connection)
      return MCP_SCOPES + [ "ads_read" ] unless connection.is_a?(Connection)

      scopes = Array(connection.granted_scopes).map(&:to_s)
      missing = MCP_SCOPES - scopes
      missing << "ads_read" unless scopes.intersect?(READ_SCOPES)
      missing
    end

    def numeric_ad_account_id(meta_ad_account_id)
      meta_ad_account_id.to_s.delete_prefix("act_")
    end
  end
end
