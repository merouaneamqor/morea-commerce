# frozen_string_literal: true

module Oauth
  module Cors
    extend ActiveSupport::Concern

    included do
      before_action :oauth_cors
    end

    private

    def oauth_cors
      headers["Access-Control-Allow-Origin"] = "*"
      headers["Access-Control-Allow-Methods"] = "GET, POST, OPTIONS"
      headers["Access-Control-Allow-Headers"] = "*"
      headers["Access-Control-Max-Age"] = "600"
    end
  end
end
