# frozen_string_literal: true

module MetaAds
  # Meta app settings come from the environment, never from source. The Graph API version is not hardcoded
  # at call sites; check https://developers.facebook.com/docs/graph-api/changelog/versions before changing the default.
  module Config
    DEFAULT_API_VERSION = "v25.0"
    BASE_URL = "https://graph.facebook.com"
    # Only these two permissions are ever requested. They are set on the Facebook Login for Business
    # configuration (META_LOGIN_CONFIG_ID), which is what the login dialog uses instead of a scope list.
    SCOPES = %w[ads_read business_management].freeze
    # Reading ad data needs ads_read; business_management only widens which ad accounts are visible.
    REQUIRED_SCOPES = %w[ads_read].freeze

    module_function

    def api_version
      version = ENV["META_GRAPH_VERSION"].presence || ENV["META_GRAPH_API_VERSION"].presence || DEFAULT_API_VERSION
      raise ArgumentError, "META_GRAPH_VERSION must look like v25.0" unless version.match?(/\Av\d{1,3}\.\d\z/)

      version
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
