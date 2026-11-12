require "rails_helper"
require "nokogiri"

RSpec.describe "Platform workspace search", type: :request do
  let(:password) { "synthetic-platform-search-password-123" }
  let!(:owner) do
    User.create!(email: "search-owner-#{SecureRandom.hex(5)}@example.test", password: password,
      super_admin: true, admin: true)
  end
  let!(:matching) do
    Store.create!(slug: "search-hit-#{SecureRandom.hex(4)}", name: "Alpha Searchable Boutique", currency: "MAD")
  end
  let!(:other) do
    Store.create!(slug: "search-miss-#{SecureRandom.hex(4)}", name: "Zeta Unrelated Workshop", currency: "MAD")
  end

  before { host! Store.base_domain }

  def sign_in(user)
    post "/admin/login", params: { email: user.email, password: password }
  end

  it "requires authentication and rejects merchant administrators" do
    get admin_platform_search_path, params: { q: matching.name }
    expect(response).to redirect_to(admin_login_path)

    merchant = matching.users.create!(email: "search-merchant-#{SecureRandom.hex(5)}@example.test",
      password: password, admin: true)
    sign_in(merchant)
    get admin_platform_search_path, params: { q: matching.name }
    expect(response).to redirect_to(admin_root_path)
  end

  it "returns matching workspaces with links to the workspace detail" do
    sign_in(owner)
    get admin_platform_search_path, params: { q: "Alpha Searchable" }

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    results = document.at_css("#search-results")
    expect(results).to be_present
    expect(results.at_css("a[href='#{admin_tenant_path(matching)}']").text).to include(matching.name)
    expect(results.text).not_to include(other.name)
    expect(response.body).not_to match(/translation missing|translation_missing/i)
  end

  it "shows an empty state for blank or unmatched queries" do
    sign_in(owner)

    get admin_platform_search_path, params: { q: "" }
    expect(response).to have_http_status(:ok)
    expect(Nokogiri::HTML(response.body).at_css("#search-results .admin-empty")).to be_present

    get admin_platform_search_path, params: { q: "no-such-workspace-#{SecureRandom.hex(6)}" }
    expect(response).to have_http_status(:ok)
    expect(Nokogiri::HTML(response.body).at_css("#search-results .admin-empty")).to be_present
  end

  it "finds a workspace by connected shop domain" do
    domain = "shop-#{SecureRandom.hex(4)}.myshopify.com"
    matching.store_connections.create!(
      provider: "shopify",
      name: "Searchable shop",
      external_domain: domain,
      shopify_oauth: true,
      shopify_app: "seallo_connect"
    )
    sign_in(owner)
    get admin_platform_search_path, params: { q: domain }

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    expect(document.at_css("#search-results a[href='#{admin_tenant_path(matching)}']")).to be_present
  end
end
