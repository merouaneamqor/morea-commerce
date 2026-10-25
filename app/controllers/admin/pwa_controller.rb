# frozen_string_literal: true

module Admin
  # Installation metadata is public and contains no workspace or session data.
  class PwaController < ApplicationController
    # A browser fetches workers without Rails' XMLHttpRequest header. This
    # endpoint serves only public static code and never reads session data.
    skip_forgery_protection only: :service_worker

    def manifest
      response.headers["Cache-Control"] = "no-cache"
      render template: "pwa/manifest", formats: [ :json ], content_type: "application/manifest+json", layout: false
    end

    def service_worker
      response.headers["Cache-Control"] = "no-cache"
      response.headers["Service-Worker-Allowed"] = "/admin"
      render template: "pwa/service-worker", formats: [ :js ], content_type: "application/javascript", layout: false
    end
  end
end
