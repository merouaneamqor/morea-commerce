# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Merchant workspace access and approval", type: :request do
  let(:suffix) { SecureRandom.hex(6) }
  let(:password) { "Synthetic-#{suffix}-password" }
  let(:platform_admin) do
    User.create!(email: "platform-#{suffix}@example.test", name: "Spec Platform Admin",
      password: password, admin: true, super_admin: true)
  end
  let(:access_request) do
    AccessRequest.create!(store_name: "Spec Merchant #{suffix}", email: "merchant-#{suffix}@example.test",
      locale: "fr", storefront_enabled: false)
  end

  before { host! Store.base_domain }

  def sign_in(user)
    post "/admin/login", params: { email: user.email, password: password }
    expect(response).to have_http_status(:redirect)
  end

  def document
    Nokogiri::HTML(response.body)
  end

  def approval_params(request_record = access_request, slug: "approved-#{suffix}", storefront_enabled: false)
    {
      access_request_id: request_record.id,
      store: { name: request_record.store_name, slug: slug, email: request_record.email,
        currency: "MAD", storefront_enabled: storefront_enabled, billing_interval: "monthly",
        billing_status: "trial", billing_amount_dh: "0" },
      admin: { email: request_record.email, password: password }
    }
  end

  describe "public signup" do
    [ false, true ].each do |storefront_enabled|
      it "requests approval without provisioning when storefront_enabled is #{storefront_enabled}" do
        expect do
          post "/signup", params: { locale: "fr", access_request: {
            store_name: "Pending Merchant #{suffix}", email: "pending-#{suffix}@example.test",
            storefront_enabled: storefront_enabled
          } }
        end.to change(AccessRequest, :count).by(1)
          .and change(Store, :count).by(0)
          .and change(User, :count).by(0)

        expect(response).to redirect_to(%r{/signup/thanks})
        request_record = AccessRequest.find_by!(email: "pending-#{suffix}@example.test")
        expect(request_record).to have_attributes(status: "pending", store_id: nil,
          reviewed_by_id: nil, reviewed_at: nil, storefront_enabled: storefront_enabled)
      end
    end
  end

  describe "the platform request queue" do
    before do
      access_request
      sign_in(platform_admin)
    end

    it "keeps pending merchants out of the workspace table and gives requests their own navigation" do
      get "/admin/platform", params: { locale: "en" }

      expect(response).to have_http_status(:ok)
      expect(document.at_css("#workspaces h2").text).to eq("Merchant workspaces")
      expect(document.at_css("#workspaces").text).not_to include(access_request.store_name, access_request.email)
      expect(document.at_css("#access-requests")).to be_nil
      expect(document.at_css(".admin-sidebar a[href='/admin/access_requests']").text).to include("Access requests")
      expect(document.at_css("[data-access-requests-count='#{AccessRequest.pending.count}']")).to be_present

      get "/admin/access_requests", params: { locale: "en" }

      expect(response).to have_http_status(:ok)
      expect(document.at_css("main").text).to include(access_request.store_name, access_request.email,
        "Shopify", "WooCommerce", "YouCan", "Review request")
      expect(document.at_css("main").text).not_to include("Visitors asking to open a store", "Create store")
    end

    { "en" => [ "Merchant workspaces", "Review request", "Approve and create workspace" ],
      "fr" => [ "Espaces marchands", "Examiner la demande", "Approuver et créer l’espace" ],
      "ar" => [ "مساحات عمل التجار", "مراجعة الطلب", "الموافقة وإنشاء مساحة العمل" ] }.each do |locale, labels|
      it "renders workspace, review and timestamp copy in #{locale}" do
        get "/admin/platform", params: { locale: locale }
        expect(document.at_css("#workspaces h2").text).to eq(labels[0])

        get "/admin/access_requests", params: { locale: locale }
        expect(response).to have_http_status(:ok)
        expect(document.at_css("html")["lang"]).to eq(locale)
        expect(document.at_css("html")["dir"]).to eq(locale == "ar" ? "rtl" : "ltr")
        review_form = document.at_css("form[action='/admin/access_requests/#{access_request.id}/approve']")
        expect(review_form.text).to include(labels[1])
        timestamp = document.at_css("time[datetime]")
        expect(Time.iso8601(timestamp["datetime"]).to_i).to eq(access_request.created_at.to_i)
        expect(timestamp.text).to eq(access_request.created_at.in_time_zone("Africa/Casablanca").strftime("%d/%m/%Y %H:%M"))
        expect(response.body).not_to match(/translation missing/i)
        expect(document.css(".translation_missing")).to be_empty

        get "/admin/tenants/new", params: { access_request_id: access_request.id, locale: locale }
        expect(response).to have_http_status(:ok)
        expect(document.at_css("input[type='submit']")["value"]).to eq(labels[2])
        expect(response.body).not_to match(/translation missing/i)
        expect(document.css(".translation_missing")).to be_empty
      end
    end

    it "opens a prefilled review form without approving or provisioning" do
      expect do
        post "/admin/access_requests/#{access_request.id}/approve"
        expect(response).to redirect_to(new_admin_tenant_path(access_request_id: access_request.id))
        follow_redirect!
      end.to change(Store, :count).by(0).and change(User, :count).by(0)

      expect(response).to have_http_status(:ok)
      expect(access_request.reload).to have_attributes(status: "pending", store_id: nil, reviewed_at: nil)
      expect(document.at_css("input[name='store[name]']")["value"]).to eq(access_request.store_name)
      expect(document.at_css("input[name='admin[email]']")["value"]).to eq(access_request.email)
      expect(document.at_css("input[name='store[storefront_enabled]'][type='checkbox']")["checked"]).to be_nil
    end
  end

  describe "approval and rejection" do
    before do
      access_request
      sign_in(platform_admin)
    end

    it "creates an external-only workspace and its first staff member without publishing shopping" do
      expect do
        post "/admin/tenants", params: approval_params
      end.to change(Store, :count).by(1).and change(User, :count).by(1)

      expect(response).to redirect_to(admin_platform_path)
      workspace = access_request.reload.store
      expect(access_request).to have_attributes(status: "approved", reviewed_by_id: platform_admin.id)
      expect(access_request.reviewed_at).to be_present
      expect(workspace.storefront_enabled).to be(false)
      expect(workspace.users.find_by!(email: access_request.email)).to have_attributes(admin: true, super_admin: false)
      expect(workspace.home_sections).to be_empty
      expect(workspace.menu_items).to be_empty

      host! "#{workspace.slug}.#{Store.base_domain}"
      %w[fr en ar].each do |locale|
        get "/#{locale}"
        expect(response).to have_http_status(:not_found)
      end
      sign_in(workspace.users.find_by!(email: access_request.email))
      get "/admin"
      expect(response).to have_http_status(:ok)
    end

    it "installs public shopping defaults when a storefront is approved" do
      access_request.update!(storefront_enabled: true)
      post "/admin/tenants", params: approval_params(storefront_enabled: true)

      expect(response).to redirect_to(admin_platform_path)
      workspace = access_request.reload.store
      expect(workspace.storefront_enabled).to be(true)
      expect(workspace.home_sections).not_to be_empty
      expect(workspace.menu_items).not_to be_empty
      host! "#{workspace.slug}.#{Store.base_domain}"
      %w[fr en ar].each do |locale|
        get "/#{locale}"
        expect(response).to have_http_status(:ok)
      end
    end

    it "rolls back provisioning and leaves the request pending if its first admin is invalid" do
      invalid_params = approval_params
      invalid_params[:admin][:password] = "x" * 73

      expect do
        post "/admin/tenants", params: invalid_params
      end.to change(Store, :count).by(0).and change(User, :count).by(0)

      expect(response).to have_http_status(422)
      expect(access_request.reload).to have_attributes(status: "pending", store_id: nil, reviewed_at: nil)
      expect(document.at_css("input[name='access_request_id']")["value"]).to eq(access_request.id.to_s)
    end

    it "records rejection without provisioning a workspace" do
      expect do
        post "/admin/access_requests/#{access_request.id}/reject"
      end.to change(Store, :count).by(0).and change(User, :count).by(0)

      expect(response).to redirect_to(admin_access_requests_path)
      expect(access_request.reload).to have_attributes(status: "rejected", store_id: nil, reviewed_by_id: platform_admin.id)
      expect(access_request.reviewed_at).to be_present
    end

    it "does not provision a second workspace from a stale approval submission" do
      post "/admin/tenants", params: approval_params
      original_workspace_id = access_request.reload.store_id
      expect(original_workspace_id).to be_present

      expect do
        post "/admin/tenants", params: approval_params(slug: "duplicate-#{suffix}")
      end.to change(Store, :count).by(0).and change(User, :count).by(0)

      expect(access_request.reload).to have_attributes(status: "approved", store_id: original_workspace_id)
    end

    it "refuses a stale provisioning submission for a rejected request" do
      post "/admin/access_requests/#{access_request.id}/reject"

      expect do
        post "/admin/tenants", params: approval_params
      end.to change(Store, :count).by(0).and change(User, :count).by(0)

      expect(access_request.reload).to have_attributes(status: "rejected", store_id: nil)
    end

    it "preserves an approved request when a stale rejection is submitted" do
      post "/admin/tenants", params: approval_params
      approved_attributes = access_request.reload.attributes.slice("status", "store_id", "reviewed_by_id", "reviewed_at")

      expect do
        post "/admin/access_requests/#{access_request.id}/reject"
      end.to change(Store, :count).by(0).and change(User, :count).by(0)

      expect(response).to redirect_to(admin_access_requests_path)
      expect(access_request.reload.attributes.slice(*approved_attributes.keys)).to eq(approved_attributes)
      follow_redirect!
      expect(response.body).to include(I18n.t("platform_admin.request_already_reviewed"))
      expect(response.body).not_to include(I18n.t("platform_admin.request_rejected"))
    end
  end

  describe "authorization" do
    [ :guest, :merchant_admin ].each do |actor|
      context "as #{actor}" do
        before do
          access_request
          next if actor == :guest

          workspace = Store.create!(name: "Staff Workspace", slug: "staff-#{suffix}", storefront_enabled: false)
          staff = workspace.users.create!(email: "staff-#{suffix}@example.test", password: password, admin: true)
          host! "#{workspace.slug}.#{Store.base_domain}"
          sign_in(staff)
        end

        it "denies reading platform workspaces, requests and the review form" do
          [ "/admin/platform", "/admin/access_requests", "/admin/tenants/new?access_request_id=#{access_request.id}" ].each do |path|
            get path
            expect(response).to have_http_status(:redirect)
            expect(response.body).not_to include(access_request.email)
          end
        end

        it "denies review, rejection and workspace provisioning without changing the request" do
          expect do
            post "/admin/access_requests/#{access_request.id}/approve"
            expect(response).to have_http_status(:redirect)
            post "/admin/access_requests/#{access_request.id}/reject"
            expect(response).to have_http_status(:redirect)
            post "/admin/tenants", params: approval_params
            expect(response).to have_http_status(:redirect)
          end.to change(Store, :count).by(0).and change(User, :count).by(0)

          expect(access_request.reload).to have_attributes(status: "pending", store_id: nil, reviewed_at: nil)
        end
      end
    end
  end
end
