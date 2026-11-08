require "rails_helper"
require "nokogiri"

RSpec.describe "Platform workspace access", type: :request do
  let(:password) { "synthetic-workspace-password-123" }
  let!(:owner) { User.create!(email: "platform-#{SecureRandom.hex(5)}@example.test", password: password, super_admin: true, admin: true) }
  let!(:first) { Store.create!(slug: "first-#{SecureRandom.hex(5)}", name: "First synthetic workspace", currency: "MAD") }
  let!(:second) { Store.create!(slug: "second-#{SecureRandom.hex(5)}", name: "Second synthetic workspace", currency: "MAD", storefront_enabled: false, subscription_required: true, billing_status: "trial") }
  let!(:first_admin) { first.users.create!(email: "first-admin-#{SecureRandom.hex(4)}@example.test", password: password, admin: true, name: "First workspace admin") }
  let!(:second_admin) { second.users.create!(email: "second-admin-#{SecureRandom.hex(4)}@example.test", password: password, admin: true, name: "Second workspace admin") }

  before { host! Store.base_domain }

  def sign_in(user)
    post "/admin/login", params: { email: user.email, password: password }
    expect(response).to have_http_status(:redirect)
  end

  def workspace_name
    Nokogiri::HTML(response.body).at_css("[data-seller-store]").text
  end

  def open_workspace(store, user)
    post enter_admin_tenant_path(store), params: { user_id: user.id }
    expect(response).to redirect_to(admin_root_path)
    follow_redirect!
    expect(response).to have_http_status(:ok)
    expect(workspace_name).to include(store.name)
    expect(response.body).to include(user.name)
  end

  it "opens and switches published and unpublished workspaces on the platform host" do
    sign_in(owner)
    [ [ first, first_admin ], [ second, second_admin ] ].each do |store, user|
      open_workspace(store, user)
      get edit_admin_store_path
      expect(response).to have_http_status(:ok)
      expect(workspace_name).to include(store.name)
      delete admin_impersonation_path
      expect(response).to redirect_to(admin_platform_path)
    end
    open_workspace(second, second_admin)
    patch admin_store_path, params: { store: { name: "Updated synthetic workspace" } }
    expect(response).to redirect_to(edit_admin_store_path)
    expect(second.reload.name).to eq("Updated synthetic workspace")
    expect(first.reload.name).to eq("First synthetic workspace")

    delete admin_impersonation_path
    expect(response).to redirect_to(admin_platform_path)
    follow_redirect!
    get admin_root_path
    expect(response).to redirect_to(admin_platform_path)
  end

  it "does not let a merchant enter another workspace" do
    merchant = first.users.create!(email: "merchant-#{SecureRandom.hex(5)}@example.test", password: password, admin: true)
    sign_in(merchant)
    post enter_admin_tenant_path(second), params: { user_id: second_admin.id }
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
    post enter_admin_tenant_path(second), params: { user_id: second_admin.id }
    expect(response).to redirect_to(admin_root_path)
    owner.update!(status: "suspended")
    get admin_root_path
    expect(response).to redirect_to(admin_login_path)
  end

  it "keeps another workspace closed while impersonating a member" do
    sign_in(owner)
    post enter_admin_tenant_path(second), params: { user_id: second_admin.id }
    get "/"
    expect(response).to have_http_status(:ok)
    host! "#{first.slug}.#{Store.base_domain}"
    get edit_admin_store_path
    expect(response).to redirect_to(admin_login_path)
  end

  it "lists only that workspace's active members in the open-admin popup" do
    agent = first.users.create!(email: "first-agent-#{SecureRandom.hex(4)}@example.test", password: password, confirmation_role: "agent", name: "First confirmation agent")
    suspended = first.users.create!(email: "first-suspended-#{SecureRandom.hex(4)}@example.test", password: password, admin: true, name: "Suspended member", status: "suspended")
    sign_in(owner)

    get admin_platform_path

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    popover = document.at_css("#impersonate-#{first.id}")
    expect(popover["popover"]).to eq("auto")
    expect(popover.text).to include(first_admin.name, first_admin.email, agent.name)
    expect(popover.text).not_to include(suspended.name, second_admin.email)
    expect(document.at_css(".admin-mobile-list")).to be_present
    expect(document.at_css("#workspaces .admin-table-wrap")["class"]).to include("hidden", "lg:block")
    expect(document.at_css("form[action='#{enter_admin_tenant_path(first)}'] input[name='user_id'][value='#{first_admin.id}']")).to be_present
  end

  it "refuses a member from another workspace, a suspended member, and a super admin" do
    suspended = first.users.create!(email: "suspended-#{SecureRandom.hex(4)}@example.test", password: password, admin: true, status: "suspended")
    sign_in(owner)

    [ second_admin.id, suspended.id, owner.id, nil ].each do |user_id|
      post enter_admin_tenant_path(first), params: { user_id: user_id }
      expect(response).to redirect_to(admin_platform_path(anchor: "workspaces"))
      expect(flash[:alert]).to eq(I18n.t("platform_admin.impersonate.invalid", locale: :fr))
    end
  end

  it "opens the workspace as the chosen confirmation agent and can return to the platform" do
    agent = first.users.create!(email: "agent-#{SecureRandom.hex(4)}@example.test", password: password, confirmation_role: "agent", name: "Chosen confirmation agent")
    sign_in(owner)

    post enter_admin_tenant_path(first), params: { user_id: agent.id }

    expect(response).to redirect_to(home_admin_confirmations_path)
    follow_redirect!
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(agent.name)
    expect(response.body).to include(I18n.t("platform_admin.impersonate.stop", locale: :fr))
    expect(response.body).not_to include(admin_platform_path)

    delete admin_impersonation_path
    expect(response).to redirect_to(admin_platform_path)
    follow_redirect!
    expect(response.body).to include(first.name)
    expect(response.body).not_to include(I18n.t("platform_admin.impersonate.stop", locale: :fr))
  end
end
