# frozen_string_literal: true

require "rails_helper"
require "nokogiri"

RSpec.describe "Platform admin user management", type: :request do
  let(:password) { "synthetic-platform-password-123" }
  let!(:store) { Store.create!(slug: "pu-#{SecureRandom.hex(5)}", name: "Synthetic managed workspace", currency: "MAD") }
  let!(:owner) { User.create!(email: "owner-#{SecureRandom.hex(4)}@example.test", password: password, admin: true, super_admin: true) }
  let!(:merchant) { store.users.create!(email: "merchant-#{SecureRandom.hex(4)}@example.test", password: password, admin: true) }

  before { host! Store.base_domain }

  def sign_in(user, pass = password)
    post "/admin/login", params: { email: user.email, password: pass, workspace: user.store&.slug }
  end

  def table_text
    Nokogiri::HTML(response.body).at_css("table").text
  end

  def lifecycle(user, action)
    post "/admin/platform/users/#{user.id}/lifecycle/#{action}"
  end

  context "when signed in as a platform administrator" do
    before { sign_in(owner) }

    it "lists workspace and platform admins" do
      get "/admin/platform/users"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(owner.email)
      get "/admin/platform/users", params: { role: "workspace_admin" }
      expect(table_text).to include(merchant.email)
      expect(table_text).not_to include(owner.email)
    end

    it "creates a workspace admin who can then sign in" do
      expect do
        post "/admin/platform/users", params: { user: { email: " New.Admin@Example.test ", name: "New", password: password, password_confirmation: password, role: "workspace_admin", store_id: store.id } }
      end.to change(User, :count).by(1)
      expect(response).to redirect_to(admin_platform_users_path)
      created = User.find_by!(email: "new.admin@example.test")
      expect([ created.store, created.admin?, created.super_admin?, created.status ]).to eq([ store, true, false, "active" ])
    end

    it "creates a platform-only super admin" do
      post "/admin/platform/users", params: { user: { email: "second-#{SecureRandom.hex(3)}@example.test", password: password, password_confirmation: password, role: "super_admin", store_id: "" } }
      expect(response).to redirect_to(admin_platform_users_path)
      expect(User.super_admins.where(store_id: nil).count).to eq(2)
    end

    it "rejects a workspace admin without a workspace or a password" do
      post "/admin/platform/users", params: { user: { email: "x-#{SecureRandom.hex(3)}@example.test", password: password, role: "workspace_admin", store_id: "" } }
      expect(response).to have_http_status(:unprocessable_content)
      post "/admin/platform/users", params: { user: { email: "y-#{SecureRandom.hex(3)}@example.test", password: "", role: "workspace_admin", store_id: store.id } }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "suspends and reactivates, blocking sign-in and live sessions while suspended" do
      merchant_session = open_session
      merchant_session.host! Store.base_domain
      merchant_session.post "/admin/login", params: { email: merchant.email, password: password }
      expect(merchant_session.response).to have_http_status(:redirect)

      lifecycle(merchant, "suspend")
      expect(merchant.reload).to be_suspended
      expect(merchant.status_changed_at).to be_present
      merchant_session.get "/admin"
      expect(URI.parse(merchant_session.response.location).path).to eq(admin_login_path)
      merchant_session.post "/admin/login", params: { email: merchant.email, password: password }
      expect(merchant_session.response).to have_http_status(:unprocessable_content)

      lifecycle(merchant, "reactivate")
      expect(merchant.reload).to be_active
      merchant_session.post "/admin/login", params: { email: merchant.email, password: password }
      expect(merchant_session.response).to have_http_status(:redirect)
    end

    it "archives and restores while keeping the record" do
      lifecycle(merchant, "archive")
      expect(merchant.reload).to be_archived
      get "/admin/platform/users", params: { status: "archived" }
      expect(response.body).to include(merchant.email)
      lifecycle(merchant, "restore")
      expect(merchant.reload).to be_active
    end

    it "refuses invalid transitions" do
      lifecycle(merchant, "restore")
      expect(response).to redirect_to(admin_platform_users_path)
      expect(merchant.reload).to be_active
    end

    it "refuses to suspend or archive your own account" do
      other = User.create!(email: "other-#{SecureRandom.hex(4)}@example.test", password: password, admin: true, super_admin: true)
      lifecycle(owner, "suspend")
      lifecycle(owner, "archive")
      expect(owner.reload).to be_active
      expect(other.reload).to be_active
    end

    it "keeps at least one active platform administrator" do
      other = User.create!(email: "other-#{SecureRandom.hex(4)}@example.test", password: password, admin: true, super_admin: true)
      lifecycle(other, "suspend")
      expect(other.reload).to be_suspended
      lifecycle(other, "reactivate")
      other_session = open_session
      other_session.host! Store.base_domain
      other_session.post "/admin/login", params: { email: other.email, password: password }
      other_session.post "/admin/platform/users/#{owner.id}/lifecycle/archive"
      expect(owner.reload).to be_archived
      other_session.post "/admin/platform/users/#{other.id}/lifecycle/archive"
      expect(other.reload).to be_active
    end

    it "does not demote yourself or the last platform administrator" do
      patch "/admin/platform/users/#{owner.id}", params: { user: { email: owner.email, role: "workspace_admin", store_id: store.id } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(owner.reload).to be_super_admin
    end

    it "does not manage workspace staff without admin access" do
      staff = store.users.create!(email: "staff-#{SecureRandom.hex(4)}@example.test", password: password, admin: false)
      get "/admin/platform/users/#{staff.id}/edit"
      expect(response).to have_http_status(:not_found)
    end

    it "rejects unknown lifecycle actions" do
      post "/admin/platform/users/#{merchant.id}/lifecycle/delete"
      expect(response).to have_http_status(:not_found)
      expect(User.exists?(merchant.id)).to be(true)
    end
  end

  it "keeps the page closed to merchants and signed-out visitors" do
    get "/admin/platform/users"
    expect(response).to redirect_to(admin_login_path)
    sign_in(merchant)
    get "/admin/platform/users"
    expect(response).to redirect_to(admin_root_path)
    post "/admin/platform/users/#{merchant.id}/lifecycle/archive"
    expect(merchant.reload).to be_active
  end

  it "does not let a suspended platform administrator keep platform access" do
    sign_in(owner)
    User.where(id: owner.id).update_all(status: "suspended")
    get "/admin/platform/users"
    expect(response).to redirect_to(admin_login_path)
  end

  it "stores only known statuses at the database level" do
    expect { merchant.update_column(:status, "deleted") }.to raise_error(ActiveRecord::StatementInvalid)
  end

  it "renders in every supported language" do
    sign_in(owner)
    %w[fr en ar].each do |locale|
      I18n.with_locale(locale) do
        expect(I18n.t("platform_users.title", raise: true)).to be_present
      end
    end
    get "/admin/platform/users"
    expect(Nokogiri::HTML(response.body).css("table").size).to eq(1)
  end
end
