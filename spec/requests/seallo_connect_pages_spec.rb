# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Seallo Connect public pages", type: :request do
  let(:paths) do
    %w[
      /seallo-connect
      /seallo-connect/pricing
      /seallo-connect/privacy
      /seallo-connect/terms
      /seallo-connect/cookies
      /seallo-connect/refunds
      /seallo-connect/privacy-rights
    ]
  end

  around do |example|
    original = ENV["SEALLO_SUPPORT_EMAIL"]
    ENV.delete("SEALLO_SUPPORT_EMAIL")
    example.run
  ensure
    original.nil? ? ENV.delete("SEALLO_SUPPORT_EMAIL") : ENV["SEALLO_SUPPORT_EMAIL"] = original
  end

  before { host! Store.base_domain }

  %w[en fr ar].each do |locale|
    it "serves every page in #{locale} without authentication" do
      paths.each do |path|
        get path, params: { locale: locale }

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("<h1>")
        expect(response.body).to include(%(dir="#{locale == "ar" ? "rtl" : "ltr"}"))
        expect(response.body).not_to include("translation missing")
      end
    end
  end

  it "describes the data the app actually reads and the privacy request handling" do
    get "/seallo-connect/privacy", params: { locale: "en" }

    expect(response.body).to include("read_orders")
    expect(response.body).to include("shipping name, phone number and delivery address")
    expect(response.body).to include("customer redaction or shop redaction")
    expect(response.body).to include("180 days")
  end

  it "publishes cookie and refund policies with transparent billing" do
    get "/seallo-connect/cookies", params: { locale: "en" }
    expect(response.body).to include("Necessary cookies")
    expect(response.body).to include("do not load Meta Pixel")

    get "/seallo-connect/refunds", params: { locale: "en" }
    expect(response.body).to include("billed by Shopify")
    expect(response.body).to include("No hidden fees")
  end

  it "shows a cookie banner on apex pages until a choice is recorded" do
    get "/seallo-connect", params: { locale: "en" }
    expect(response.body).to include("cookie-consent")
    expect(response.body).to include("skip-link")

    post tracking_consent_path, params: { choice: "denied" }, as: :json
    expect(response).to have_http_status(:no_content)
    expect(cookies["morea_tracking_consent"]).to eq("denied")

    get "/seallo-connect", params: { locale: "en" }
    expect(response.body).not_to include('data-controller="tracking-consent"')
  end

  it "records a platform data-rights request" do
    expect {
      post "/seallo-connect/privacy-rights", params: {
        locale: "en",
        platform_privacy_rights_request: {
          request_type: "access",
          requester_name: "Merchant",
          requester_contact: "merchant@example.test",
          shop_domain: "example.myshopify.com"
        }
      }
    }.to change(PlatformPrivacyRightsRequest, :count).by(1)

    expect(response).to redirect_to(%r{/seallo-connect/privacy-rights})
  end

  it "publishes the four plans, unlimited Business imports and the trial" do
    get "/seallo-connect/pricing", params: { locale: "en" }

    expect(response.body).to include("Seallo Starter: $19 per month")
    expect(response.body).to include("Seallo Intermediate: $39 per month")
    expect(response.body).to include("Seallo Professionnel: $59 per month")
    expect(response.body).to include("Seallo Business: $129 per month")
    expect(response.body).to include("Unlimited imported orders")
    expect(response.body).to include("7-day free trial on paid plans")
  end

  it "links the pricing page from every page's navigation" do
    paths.reject { |path| path.end_with?("privacy-rights") }.each do |path|
      get path, params: { locale: "en" }
      expect(response.body).to include(%(href="/seallo-connect/pricing))
    end
  end

  it "shows a configured support address as a mail link" do
    ENV["SEALLO_SUPPORT_EMAIL"] = "support@synthetic.test"

    get "/seallo-connect", params: { locale: "en" }

    expect(response.body).to include(%(href="mailto:support@synthetic.test"))
  end

  it "ignores a malformed support address instead of rendering it" do
    ENV["SEALLO_SUPPORT_EMAIL"] = %("><script>alert(1)</script>)

    get "/seallo-connect/privacy", params: { locale: "en" }

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("<script>alert(1)</script>")
    expect(response.body).not_to include("mailto:")
    expect(response.body).to include("through your Seallo workspace")
  end

  it "is not published on a tenant host" do
    store = Store.create!(slug: "pages-#{SecureRandom.hex(4)}", name: "Synthetic workspace", currency: "MAD", storefront_enabled: false)
    host! "#{store.slug}.#{Store.base_domain}"

    get "/seallo-connect/privacy"

    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include("read_orders")
  end

  it "keeps the three translations structurally identical" do
    shape = lambda do |locale|
      %i[overview pricing privacy terms cookie_policy refunds].to_h do |page|
        copy = I18n.t("seallo_connect_pages.#{page}", locale: locale)
        [ page, copy[:sections].map { |section| [ section[:body].to_a.size, section[:items].to_a.size ] } ]
      end
    end

    expect(shape.call(:fr)).to eq(shape.call(:en))
    expect(shape.call(:ar)).to eq(shape.call(:en))
  end
end
