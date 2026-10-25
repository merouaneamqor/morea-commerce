require "rails_helper"
require "nokogiri"

RSpec.describe "Platform workspace access", type: :request do
  let(:password) { "synthetic-workspace-password-123" }
  let!(:owner) { User.create!(email: "platform-#{SecureRandom.hex(5)}@example.test", password: password, super_admin: true, admin: true) }
  let!(:first) { Store.create!(slug: "first-#{SecureRandom.hex(5)}", name: "First synthetic workspace", currency: "MAD") }
  let!(:second) { Store.create!(slug: "second-#{SecureRandom.hex(5)}", name: "Second synthetic workspace", currency: "MAD", storefront_enabled: false, subscription_required: true, billing_status: "trial") }

  before { host! Store.base_domain }

  def sign_in(user)
    post "/admin/login", params: { email: user.email, password: password }
    expect(response).to have_http_status(:redirect)
  end

  def workspace_name
    Nokogiri::HTML(response.body).at_css(".admin-topbar__brand").text
  end

  it "opens and switches published and unpublished workspaces on the platform host" do
    sign_in(owner)
    [ first, second ].each do |store|
      post enter_admin_tenant_path(store)
      expect(response).to redirect_to(admin_root_path)
      follow_redirect!
      expect(response).to have_http_status(:ok)
      expect(workspace_name).to include(store.name)
      get edit_admin_store_path
      expect(response).to have_http_status(:ok)
      expect(workspace_name).to include(store.name)
    end
    patch admin_store_path, params: { store: { name: "Updated synthetic workspace" } }
    expect(response).to redirect_to(edit_admin_store_path)
    expect(second.reload.name).to eq("Updated synthetic workspace")
    expect(first.reload.name).to eq("First synthetic workspace")

    get admin_platform_path
    get admin_root_path
    expect(response).to redirect_to(admin_platform_path)
  end

  it "does not let a merchant enter another workspace" do
    merchant = first.users.create!(email: "merchant-#{SecureRandom.hex(5)}@example.test", password: password, admin: true)
    sign_in(merchant)
    post enter_admin_tenant_path(second)
    expect(response).to redirect_to(admin_root_path)
    get edit_admin_store_path
    expect(workspace_name).to include(first.name)
    expect(workspace_name).not_to include(second.name)
  end

  it "requires authentication and rejects nonexistent workspaces" do
    post enter_admin_tenant_path(first)
    expect(response).to redirect_to(admin_login_path)
    sign_in(owner)
    post enter_admin_tenant_path(Store.maximum(:id) + 1)
    expect(response).to have_http_status(:not_found)
  end

  it "invalidates workspace access when the platform account is suspended" do
    sign_in(owner)
    post enter_admin_tenant_path(second)
    owner.update!(status: "suspended")
    get admin_root_path
    expect(response).to redirect_to(admin_login_path)
  end

  it "keeps public storefront context tied to the requested host" do
    sign_in(owner)
    post enter_admin_tenant_path(second)
    get "/"
    expect(response).to have_http_status(:ok)
    host! "#{first.slug}.#{Store.base_domain}"
    get edit_admin_store_path
    expect(workspace_name).to include(first.name)
  end
end
