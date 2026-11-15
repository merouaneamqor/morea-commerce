# frozen_string_literal: true

module CatalogTools
  module MetaAdsMcp
    # Read-only Meta Ads MCP tools that may be proxied without confirm.
    READ_TOOLS = %w[
      ads_get_ad_accounts
      ads_get_ad_entities
      ads_get_opportunity_score
      ads_get_field_context
      ads_insights_advertiser_context
      ads_insights_anomaly_signal
      ads_insights_auction_ranking_benchmarks
      ads_insights_industry_benchmark
      ads_insights_performance_trend
      ads_library_search
    ].freeze

    module_function

    def json_ok(payload)
      MCP::Tool::Response.new([ { type: "text", text: JSON.generate(payload) } ])
    end

    def json_error(message, code: "error")
      MCP::Tool::Response.new([ { type: "text", text: JSON.generate(error: message, code: code) } ], error: true)
    end

    def connection_for(store)
      store.meta_ads_connection
    end

    class MetaAdsStatus < MCP::Tool
      description <<~TEXT.squish
        Meta Ads connection status for this store: Graph OAuth status, granted scopes,
        whether Meta's hosted Ads MCP (mcp.facebook.com/ads) is usable, and selected ad accounts.
        Does not call Meta. Secrets and tokens are never returned.
      TEXT

      def self.call(server_context:)
        store = CatalogExecutor.store_from(server_context)
        connection = MetaAdsMcp.connection_for(store)
        accounts = connection ? connection.ad_accounts.where(store_id: store.id).order(:name).limit(50) : []
        MetaAdsMcp.json_ok(
          connected: connection&.active? || false,
          status: connection&.status || "disconnected",
          mcpReady: MetaAds::McpCapability.ready?(connection),
          mcpMissingScopes: MetaAds::McpCapability.missing_scopes(connection),
          mcpUrl: MetaAds::Config.mcp_url,
          syncViaMcp: MetaAds::McpCapability.sync_via_mcp?,
          grantedScopes: Array(connection&.granted_scopes),
          tokenExpiresAt: connection&.token_expires_at&.iso8601,
          adAccounts: accounts.map { |account|
            {
              id: account.meta_ad_account_id,
              numericId: MetaAds::McpCapability.numeric_ad_account_id(account.meta_ad_account_id),
              name: account.name,
              selected: account.selected?,
              currency: account.currency,
              syncStatus: account.sync_status
            }
          }
        )
      end
    end

    class MetaAdsListMcpTools < MCP::Tool
      description <<~TEXT.squish
        List tools exposed by Meta's hosted Ads MCP for this store's connected Meta user.
        Requires an active Meta connection with ads_mcp_management plus ads_read (or ads_management).
        Reconnect Meta in Seallo admin if mcpReady is false. Never returns tokens.
      TEXT

      def self.call(server_context:)
        store = CatalogExecutor.store_from(server_context)
        connection = MetaAdsMcp.connection_for(store)
        return MetaAdsMcp.json_error("Meta Ads is not connected.", code: "not_connected") unless connection&.active?
        return MetaAdsMcp.json_error("Reconnect Meta and grant Ads MCP permissions.", code: "mcp_scopes_missing") unless MetaAds::McpCapability.ready?(connection)

        listed = MetaAds::McpClient.new(connection: connection).list_tools
        tools = Array(listed.result.is_a?(Hash) ? listed.result["tools"] : listed.result)
        MetaAdsMcp.json_ok(
          count: tools.size,
          tools: tools.filter_map { |tool|
            next unless tool.is_a?(Hash)

            { name: tool["name"], description: tool["description"].to_s.truncate(240) }
          }
        )
      rescue MetaAds::McpClient::AuthError, MetaAds::McpClient::PermissionError
        MetaAdsMcp.json_error("Meta Ads MCP authorization failed. Reconnect Meta.", code: "reauthorization_required")
      rescue MetaAds::McpClient::Error => error
        MetaAdsMcp.json_error("Meta Ads MCP unavailable.", code: error.code)
      end
    end

    class MetaAdsCallMcpTool < MCP::Tool
      description <<~TEXT.squish
        Call one tool on Meta's hosted Ads MCP using this store's Meta connection token.
        Read tools (ads_get_ad_accounts, ads_get_ad_entities, insights_*, …) run without confirm.
        Any other tool name is treated as a write/management call and requires confirm: true
        (and usually ads_management on the Meta connection). Pass arguments as a JSON object.
        Prefer numeric ad_account_id without the act_ prefix for ads_get_ad_entities.
      TEXT
      input_schema(
        properties: {
          tool: { type: "string", description: "Meta Ads MCP tool name, e.g. ads_get_ad_entities" },
          arguments: { type: "object", description: "Tool arguments as JSON object" },
          confirm: { type: "boolean", description: "Required true for non-read tools" }
        },
        required: %w[tool]
      )

      def self.call(server_context:, tool:, arguments: nil, confirm: false)
        store = CatalogExecutor.store_from(server_context)
        connection = MetaAdsMcp.connection_for(store)
        return MetaAdsMcp.json_error("Meta Ads is not connected.", code: "not_connected") unless connection&.active?
        return MetaAdsMcp.json_error("Reconnect Meta and grant Ads MCP permissions.", code: "mcp_scopes_missing") unless MetaAds::McpCapability.ready?(connection)

        name = tool.to_s.strip
        return MetaAdsMcp.json_error("tool is required.", code: "invalid") if name.blank?

        read = READ_TOOLS.include?(name) || name.start_with?("ads_insights_") || name.start_with?("ads_get_")
        unless read
          return MetaAdsMcp.json_error("confirm: true is required for this Meta Ads MCP tool.", code: "confirm_required") unless confirm == true
        end

        args = arguments.is_a?(Hash) ? arguments : {}
        response = MetaAds::McpClient.new(connection: connection).call_tool(name, args)
        payload = response.tool_json
        MetaAdsMcp.json_ok(tool: name, result: payload.nil? ? { text: response.tool_text.to_s.truncate(8_000) } : payload)
      rescue MetaAds::McpClient::AuthError, MetaAds::McpClient::PermissionError
        MetaAdsMcp.json_error("Meta Ads MCP authorization failed. Reconnect Meta.", code: "reauthorization_required")
      rescue MetaAds::McpClient::ToolError
        MetaAdsMcp.json_error("Meta Ads MCP tool returned an error.", code: "tool_error")
      rescue MetaAds::McpClient::Error => error
        MetaAdsMcp.json_error("Meta Ads MCP unavailable.", code: error.code)
      end
    end
  end
end
