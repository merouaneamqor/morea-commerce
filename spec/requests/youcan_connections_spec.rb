# frozen_string_literal: true

require "rails_helper"

RSpec.describe "YouCan store authorization", type: :request do
  let(:password) { "synthetic-youcan-password-123" }
  let(:store) { Store.create!(slug: "youcan-ui-#{SecureRandom.hex(4)}", name: "Synthetic YouCan workspace", currency: "MAD", storefront_enabled: false) }
  let(:staff) { store.users.create!(email: "youcan-#{SecureRandom.hex(4)}@example.test", password: password, admin: true) }

  before do
    host! Store.base_domain
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("YOUCAN_CLIENT_ID").and_return("cl_synthetic")
    allow(ENV).to receive(:[]).with("YOUCAN_CLIENT_SECRET").and_return("synthetic-youcan-client-secret")
  end

  def sign_in
    host! "#{store.slug}.#{Store.base_domain}"
    post "/admin/login", params: { email: staff.email, password: password }
    expect(response).to have_http_status(:redirect)
  end

  def authorization_state
    sign_in
    get "/admin/youcan/connect"
    expect(response).to have_http_status(:redirect)
    Rack::Utils.parse_query(URI(response.location).query).fetch("state")
  end

  it "requires sign-in and returns to the YouCan connection afterward" do
    get "/admin/youcan/connect"
    expect(response).to redirect_to(admin_login_path)
    expect(session[:return_to]).to eq("/admin/youcan/connect")
  end

  it "sends the workspace to YouCan with the store identity and webhook scopes" do
    sign_in
    get "/admin/youcan/connect"

    expect(response).to have_http_status(:redirect)
    expect(response.headers["Cache-Control"]).to include("no-store")
    location = response.location
    expect(location).to start_with("https://seller-area.youcan.shop/admin/oauth/authorize?")
    query = Rack::Utils.parse_query(URI(location).query)
    expect(query).to include(
      "client_id" => "cl_synthetic",
      "redirect_uri" => "#{Store.platform_origin}/admin/youcan/callback",
      "response_type" => "code"
    )
    expect(query["state"]).to match(/\A[0-9a-f]{48}\z/)
    expect(location).to include("scope[]=view-store-info", "scope[]=edit-rest-hooks")
    expect(location).not_to include("read-orders", "synthetic-youcan-client-secret")
  end

  it "explains that YouCan is not configured instead of sending the seller away" do
    allow(ENV).to receive(:[]).with("YOUCAN_CLIENT_SECRET").and_return("")
    sign_in
    get "/admin/youcan/connect"

    expect(response).to have_http_status(:service_unavailable)
    expect(response.body).to include(I18n.t("connections.youcan_oauth.unavailable"))
    expect(response.location).to be_nil
  end

  it "stores the approved store and forgets the authorization request" do
    state = authorization_state
    connection = store.store_connections.new(provider: "youcan", name: "Seallo", external_domain: "seallo.youcan.store",
      external_store_id: "0ff0817b-4f5a-43e9-b42d-066363aa45e3", webhook_secret: "synthetic-youcan-client-secret")
    connection.save!
    allow(Connections::YoucanOauth).to receive(:connect!).and_return(connection)

    get "/admin/youcan/callback", params: { code: "synthetic-code", state: state }

    expect(response).to redirect_to(admin_store_connection_path(connection))
    expect(flash[:notice]).to eq(I18n.t("connections.youcan_oauth.connected"))
    expect(Connections::YoucanOauth).to have_received(:connect!).with(store: store, code: "synthetic-code")

    get "/admin/youcan/callback", params: { code: "synthetic-code", state: state }
    expect(response).to redirect_to(admin_store_connections_path)
    expect(flash[:alert]).to eq(I18n.t("connections.youcan_oauth.invalid"))
  end

  it "does not exchange a canceled or mismatched approval" do
    state = authorization_state
    allow(Connections::YoucanOauth).to receive(:connect!)

    get "/admin/youcan/callback", params: { error: "access_denied", state: state }
    expect(response).to redirect_to(admin_store_connections_path)
    expect(flash[:alert]).to eq(I18n.t("connections.youcan_oauth.denied"))

    state = authorization_state
    get "/admin/youcan/callback", params: { code: "synthetic-code", state: "f" * 48 }
    expect(response).to redirect_to(admin_store_connections_path)
    expect(flash[:alert]).to eq(I18n.t("connections.youcan_oauth.invalid"))
    expect(Connections::YoucanOauth).not_to have_received(:connect!)
  end
end
