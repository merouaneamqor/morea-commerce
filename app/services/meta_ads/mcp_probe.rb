# frozen_string_literal: true

module MetaAds
  # Admin/ops read of Meta Ads MCP readiness and a safe tools/list (+ optional entities sample).
  class McpProbe
    Result = Struct.new(:ready, :missing_scopes, :tool_count, :tool_names, :sample, :error_code, keyword_init: true)

    def initialize(connection:, ad_account: nil, transport: nil)
      @connection = connection
      @ad_account = ad_account
      @transport = transport
    end

    def call
      missing = McpCapability.missing_scopes(@connection)
      return Result.new(ready: false, missing_scopes: missing, tool_count: 0, tool_names: [], sample: nil, error_code: "mcp_scopes_missing") unless McpCapability.ready?(@connection)

      client = McpClient.new(connection: @connection, transport: @transport)
      listed = client.list_tools
      tools = Array(listed.result.is_a?(Hash) ? listed.result["tools"] : listed.result)
      names = tools.filter_map { |tool| tool["name"] if tool.is_a?(Hash) }
      sample = nil
      if @ad_account
        response = client.call_tool(
          "ads_get_ad_entities",
          ad_account_id: McpCapability.numeric_ad_account_id(@ad_account.meta_ad_account_id),
          level: "campaign",
          fields: %w[id name amount_spent],
          date_preset: "last_7d",
          limit: 5
        )
        sample = response.tool_json || { text: response.tool_text.to_s.truncate(2_000) }
      end
      Result.new(ready: true, missing_scopes: [], tool_count: names.size, tool_names: names.first(50), sample: sample, error_code: nil)
    rescue McpClient::Error => error
      Result.new(ready: false, missing_scopes: missing, tool_count: 0, tool_names: [], sample: nil, error_code: error.code)
    end
  end
end
