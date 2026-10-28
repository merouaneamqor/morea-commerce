# frozen_string_literal: true

module MetaAds
  # Meta app settings come from the environment. The Graph API version is never hardcoded at call sites;
  # check https://developers.facebook.com/docs/graph-api/changelog/versions before changing the default.
  module Config
    DEFAULT_API_VERSION = "v25.0"
    BASE_URL = "https://graph.facebook.com"
    # Phase 1 is read-only. ads_management belongs to a later phase with its own review.
    SCOPES = %w[ads_read].freeze

    module_function

    def api_version
      version = ENV["META_GRAPH_API_VERSION"].presence || DEFAULT_API_VERSION
      raise ArgumentError, "META_GRAPH_API_VERSION must look like v25.0" unless version.match?(/\Av\d{1,3}\.\d\z/)

      version
    end

    def app_id
      ENV["META_APP_ID"].presence
    end

    def app_secret
      ENV["META_APP_SECRET"].presence
    end

    def configured?
      app_id.present? && app_secret.present?
    end
  end
end
