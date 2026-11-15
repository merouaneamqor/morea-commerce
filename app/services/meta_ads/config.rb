# frozen_string_literal: true

module MetaAds
  # Meta app settings come from the environment, never from source. The Graph API version is not hardcoded
  # at call sites; check https://developers.facebook.com/docs/graph-api/changelog/versions before changing the default.
  module Config
    DEFAULT_API_VERSION = "v25.0"
    BASE_URL = "https://graph.facebook.com"
    # Permissions the Facebook Login for Business configuration (META_LOGIN_CONFIG_ID) should request.
    # The login dialog uses that config, not this list as a query param. Keep Graph read scopes, and
    # add ads_mcp_management so Seallo can call Meta's hosted Ads MCP with the same merchant token.
    SCOPES = %w[ads_read business_management ads_mcp_management].freeze
    # Connecting still requires ads_read so Graph spend sync keeps working before MCP App Review lands.
    REQUIRED_SCOPES = %w[ads_read].freeze
    # Ready for https://mcp.facebook.com/ads (Meta: ads_mcp_management + ads_read or ads_management).
    MCP_REQUIRED_SCOPES = %w[ads_mcp_management ads_read].freeze

    module_function

    def api_version
      version = ENV["META_GRAPH_VERSION"].presence || ENV["META_GRAPH_API_VERSION"].presence || DEFAULT_API_VERSION
      raise ArgumentError, "META_GRAPH_VERSION must look like v25.0" unless version.match?(/\Av\d{1,3}\.\d\z/)

      version
    end

    def mcp_url
      ENV["META_ADS_MCP_URL"].presence || "https://mcp.facebook.com/ads"
    end

    def app_id
      ENV["META_APP_ID"].presence
    end

    def app_secret
      ENV["META_APP_SECRET"].presence
    end

    def login_config_id
      ENV["META_LOGIN_CONFIG_ID"].presence
    end

    # The one redirect URI registered with Meta, on the platform apex: https://<apex>/auth/meta/callback.
    def redirect_uri
      ENV["META_REDIRECT_URI"].presence
    end

    def configured?
      [ app_id, app_secret, login_config_id, redirect_uri ].all?(&:present?)
    end
  end
end
