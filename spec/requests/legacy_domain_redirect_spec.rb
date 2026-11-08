# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Legacy domain redirect", type: :request do
  def with_domains
    previous = ENV.to_hash.slice("APP_BASE_DOMAIN", "LEGACY_BASE_DOMAIN")
    ENV["APP_BASE_DOMAIN"] = "seallo.ma"
    ENV["LEGACY_BASE_DOMAIN"] = "ollazen.com"
    yield
  ensure
    previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    ( %w[APP_BASE_DOMAIN LEGACY_BASE_DOMAIN] - previous.keys ).each { |key| ENV.delete(key) }
  end

  it "redirects the apex host to the canonical domain" do
    with_domains do
      host! "ollazen.com"
      get "/admin"
      expect(response).to redirect_to("https://seallo.ma/admin")
      expect(response).to have_http_status(:moved_permanently)
    end
  end

  it "redirects www to the canonical apex" do
    with_domains do
      host! "www.ollazen.com"
      get "/signup"
      expect(response).to redirect_to("https://seallo.ma/signup")
    end
  end

  it "preserves tenant subdomains on the canonical domain" do
    with_domains do
      host! "morea.ollazen.com"
      get "/admin/orders?status=new"
      expect(response).to redirect_to("https://morea.seallo.ma/admin/orders?status=new")
    end
  end

  it "does not redirect the health check on a legacy host" do
    with_domains do
      host! "ollazen.com"
      get "/up"
      expect(response).to have_http_status(:ok)
    end
  end
end
