# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Seallo Connect public pages", type: :request do
  let(:paths) { %w[/seallo-connect /seallo-connect/pricing /seallo-connect/privacy /seallo-connect/terms] }

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
  end

  it "publishes the three plans, their allowances and the trial" do
    get "/seallo-connect/pricing", params: { locale: "en" }

    expect(response.body).to include("Seallo Basic: Free", "Fewer than 20 imported orders")
    expect(response.body).to include("Seallo Pro: $9 per month", "For 20–99 imported orders")
    expect(response.body).to include("Seallo Premium: $27 per month", "Unlimited imported orders")
    expect(response.body).to include("7-day free trial on paid plans")
  end

  it "links the pricing page from every page's navigation" do
    paths.each do |path|
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
      %i[overview pricing privacy terms].to_h do |page|
        copy = I18n.t("seallo_connect_pages.#{page}", locale: locale)
        [ page, copy[:sections].map { |section| [ section[:body].to_a.size, section[:items].to_a.size ] } ]
      end
    end

    expect(shape.call(:fr)).to eq(shape.call(:en))
    expect(shape.call(:ar)).to eq(shape.call(:en))
  end
end
