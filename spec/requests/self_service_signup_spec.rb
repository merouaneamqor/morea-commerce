# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Self-service merchant signup", type: :request do
  let(:suffix) { SecureRandom.hex(6) }
  let(:password) { "Synthetic-signup-#{suffix}" }
  let(:email) { "owner-#{suffix}@example.test" }
  let(:attributes) do
    { business_name: "Synthetic Workspace #{suffix}", email: email }
  end
  let(:signup_fields) do
    { name: "Youssef El Amrani", store_name: "Boutique #{suffix}", phone: "06 12 34 56 78", email: email,
      password: password, password_confirmation: password, currency: "USD" }
  end

  before { host! Store.base_domain }

  def sign_up(**overrides)
    post "/signup", params: { signup: signup_fields.merge(overrides), locale: "en" }
  end

  def pending_registration
    Registration.create!(attributes.merge(locale: "en", verification_sent_at: Time.current))
  end

  def document
    Nokogiri::HTML(response.body)
  end

  describe "step 1: account" do
    it "creates the workspace and owner directly on the free plan and signs them in" do
      expect { sign_up(email: "  #{email.upcase}  ") }.to change(Store, :count).by(1).and change(User, :count).by(1)

      expect(response).to redirect_to(%r{/admin(\?|\z)})
      owner = User.find_by!(email: email)
      expect(owner).to have_attributes(admin: true, super_admin: false)
      expect(owner.authenticate(password)).to eq(owner)
      expect(owner.store).to have_attributes(plan: "free", currency: "USD", phone: "0612345678", storefront_enabled: false,
        subscription_required: false, billing_status: "active", admin_theme: "seallo")
      follow_redirect!
      expect(response).to have_http_status(:ok)
    end

    it "applies a plan chosen as a guest, starts the trial and continues to payment" do
      post "/abonnement", params: { plan: "starter", billing: "annual", currency: "EUR" }
      expect(response).to redirect_to(signup_path(locale: I18n.locale))
      get "/signup", params: { locale: "en" }
      expect(document.at_css("select[name='signup[currency]'] option[selected]")["value"]).to eq("EUR")

      sign_up(currency: "EUR")
      expect(response).to redirect_to(payment_path(locale: I18n.locale))
      store = User.find_by!(email: email).store
      expect(store).to have_attributes(plan: "starter", billing_interval: "yearly", billing_status: "trial",
        subscription_required: true, currency: "EUR")
      expect(store.trial_ends_at).to be_within(1.minute).of(7.days.from_now)
      expect(store.operational_access?).to be(true)
    end

    it "validates the account fields without creating anything" do
      [ { phone: "123" }, { name: "" }, { store_name: "" }, { email: "not-an-email" }, { currency: "XXX" },
        { password: "short", password_confirmation: "short" }, { password_confirmation: "does-not-match" } ].each do |invalid|
        expect { sign_up(**invalid) }.to change(Store, :count).by(0).and change(User, :count).by(0)
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    it "rejects an email that already has an account or a pending registration" do
      workspace = Store.create!(name: "Existing", slug: "existing-#{suffix}")
      workspace.users.create!(email: "existing-#{email}", password: password, admin: true)
      pending_registration
      [ "existing-#{email}", email ].each do |taken|
        expect { sign_up(email: taken) }.to change(Store, :count).by(0).and change(User, :count).by(0)
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    it "ignores the honeypot without creating an identity" do
      expect do
        post "/signup", params: { signup: signup_fields, website: "https://bot.example.test" }
      end.to change(Store, :count).by(0).and change(User, :count).by(0)
      expect(response).to redirect_to(%r{://[^/]+/(\?|\z)})
    end

    it "limits signup attempts by IP without provisioning accounts" do
      memory_store = ActiveSupport::Cache::MemoryStore.new
      # Rails captures the configured cache instance when declaring rate_limit.
      allow(SignupsController.cache_store).to receive(:increment) do |*args, **options|
        memory_store.increment(*args, **options)
      end
      headers = { "REMOTE_ADDR" => "203.0.113.51" }
      expect do
        10.times do
          post "/signup", params: { signup: signup_fields, website: "https://bot.example.test" }, headers: headers
          expect(response).to have_http_status(:redirect)
        end
        post "/signup", params: { signup: signup_fields }, headers: headers
        expect(response).to have_http_status(:too_many_requests)
        post "/signup", params: { signup: signup_fields, website: "https://bot.example.test" },
          headers: { "REMOTE_ADDR" => "203.0.113.52" }
        expect(response).to have_http_status(:redirect)
      end.to change(Store, :count).by(0).and change(User, :count).by(0)
    end

    it "refuses self-service signup on a tenant host" do
      store = Store.create!(name: "Tenant", slug: "tenant-#{suffix}")
      host! "#{store.slug}.#{Store.base_domain}"
      get "/signup"
      expect(response).to have_http_status(:not_found)
      expect { sign_up }.not_to change(User, :count)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "step 2: plan" do
    def sign_in_new_owner
      sign_up
      User.find_by!(email: email)
    end

    it "shows the plans with or without an account" do
      get "/abonnement", params: { locale: "en" }
      expect(response).to have_http_status(:ok)
      expect(document.at_css("[data-plans]")["data-guest"]).to eq("true")
      expect(JSON.parse(document.at_css("[data-plans]")["data-config"])["list"].keys).to eq(%w[free starter intermediate professional business])
      expect(response.body).not_to include(Plans.bank["rib"])
      sign_in_new_owner
      get "/abonnement", params: { locale: "en" }
      expect(document.at_css("[data-plans]")["data-guest"]).to eq("false")
    end

    it "starts the trial on the first paid choice and never restarts it (payment step on)" do
      allow(Plans).to receive(:skip_payment?).and_return(false)
      owner = sign_in_new_owner
      post "/abonnement", params: { plan: "intermediate", billing: "monthly", currency: "MAD" }
      expect(response).to redirect_to(payment_path(locale: I18n.locale))
      store = owner.store.reload
      first_trial = store.trial_ends_at
      expect(store).to have_attributes(plan: "intermediate", billing_status: "trial", subscription_required: true, currency: "MAD")

      travel 2.days do
        post "/abonnement", params: { plan: "professional", billing: "annual", currency: "MAD" }
        expect(store.reload.trial_ends_at).to eq(first_trial)
        expect(store).to have_attributes(plan: "professional", billing_interval: "yearly")
      end
    end

    it "lets a seller go back to the free plan, which needs no payment" do
      owner = sign_in_new_owner
      post "/abonnement", params: { plan: "starter", billing: "monthly", currency: "USD" }
      post "/abonnement", params: { plan: "free", billing: "monthly", currency: "USD" }
      expect(response).to redirect_to(%r{/admin(\?|\z)})
      expect(owner.store.reload).to have_attributes(plan: "free", subscription_required: false)
    end

    it "rejects unknown plans, billings and currencies" do
      owner = sign_in_new_owner
      [ { plan: "gold" }, { billing: "weekly" }, { currency: "XXX" } ].each do |invalid|
        post "/abonnement", params: { plan: "starter", billing: "monthly", currency: "USD" }.merge(invalid)
        expect(response).to redirect_to(plans_path(locale: I18n.locale))
      end
      expect(owner.store.reload.plan).to eq("free")
    end

    it "leaves workspaces that predate plans on their existing billing policy" do
      legacy = Store.create!(name: "Legacy", slug: "legacy-#{suffix}", currency: "MAD")
      legacy.users.create!(email: "legacy-#{email}", password: password, admin: true)
      post "/admin/login", params: { email: "legacy-#{email}", password: password }
      post "/abonnement", params: { plan: "starter", billing: "monthly", currency: "USD" }
      expect(response).to redirect_to(%r{/admin(\?|\z)})
      expect(legacy.reload).to have_attributes(plan: nil, subscription_required: false)
      get "/paiement"
      expect(response).to redirect_to(%r{/admin(\?|\z)})
    end
  end

  describe "step 3: payment" do
    let!(:owner) do
      post "/abonnement", params: { plan: "starter", billing: "annual", currency: "MAD" }
      sign_up
      User.find_by!(email: email)
    end

    it "requires an account and a paid plan" do
      delete "/admin/logout"
      get "/paiement"
      expect(response).to redirect_to(%r{/admin/login})
      sign_up(email: "free-#{email}")
      get "/paiement"
      expect(response).to redirect_to(%r{/abonnement})
    end

    it "shows the summary, the bank details and the trial end" do
      get "/paiement", params: { locale: "en" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(Plans.bank["rib"], Plans.bank["holder"])
      expect(response.body).to include(Plans.money(Plans.amount_due("starter", "annual"), "USD"))
      expect(document.at_css("time[data-long-date]")["datetime"]).to eq(owner.store.trial_ends_at.to_date.iso8601)
    end

    it "records one pending transfer and updates it instead of adding another" do
      expect { post "/paiement/virement", params: { reference: "VIR-1" } }.to change(Payment, :count).by(1)
      payment = owner.store.payments.sole
      expect(payment).to have_attributes(plan: "starter", billing: "annual", amount: 190, status: "pending", payment_method: "transfer", reference: "VIR-1")
      expect { post "/paiement/virement", params: { reference: "VIR-2" } }.not_to change(Payment, :count)
      expect(payment.reload.reference).to eq("VIR-2")
      get "/paiement", params: { locale: "en" }
      expect(response.body).to include("VIR-2")
    end

    it "rejects a missing or oversized reference" do
      [ "", " ", "x" * 101 ].each do |reference|
        expect { post "/paiement/virement", params: { reference: reference } }.not_to change(Payment, :count)
        expect(response).to redirect_to(payment_path(locale: I18n.locale))
      end
    end
  end

  describe "trial access" do
    it "gives operational access during the trial and not after it ends unpaid" do
      post "/abonnement", params: { plan: "starter", billing: "monthly", currency: "USD" }
      sign_up
      store = User.find_by!(email: email).store
      get "/admin/products"
      expect(response).to have_http_status(:ok)
      travel 8.days do
        expect(store.reload.operational_access?).to be(false)
        get "/admin/products"
        expect(response).to redirect_to(admin_subscription_path)
      end
    end
  end

  %w[fr en ar].each do |locale|
    it "renders localized signup, plans, sign-in and legacy verification pages in #{locale}" do
      registration = pending_registration
      [ [ "/signup", {} ], [ "/abonnement", {} ], [ "/admin/login", {} ], [ "/signup/thanks", {} ],
        [ "/signup/verify", { token: registration.verification_token } ] ].each do |path, params|
        get path, params: params.merge(locale: locale)
        expect(response).to have_http_status(:ok)
        expect(document.at_css("html")["lang"]).to eq(locale)
        expect(response.body).not_to match(/translation missing/i)
      end
    end
  end

  # Verification links already sent keep working for registrations created before direct signup.
  describe "pending email registrations" do
    it "does not provision or sign in from a verification GET" do
      registration = pending_registration
      expect do
        get "/signup/verify", params: { token: registration.verification_token }
      end.to change(Store, :count).by(0).and change(User, :count).by(0)
      expect(response).to have_http_status(:ok)
      expect(registration.reload).not_to be_verified
      expect(document.at_css("form[action*='/signup/confirm']")).to be_present
      get "/admin"
      expect(response).to redirect_to(admin_login_path)
    end

    it "provisions one unpublished, subscription-gated workspace after explicit confirmation" do
      registration = pending_registration
      token = registration.verification_token
      expect do
        post signup_confirm_path, params: { token: token, password: password, password_confirmation: password }
      end.to change(Store, :count).by(1).and change(User, :count).by(1)
      expect(response).to redirect_to(admin_root_path(locale: I18n.locale))
      owner = registration.reload.user
      expect(registration).to be_verified
      expect(owner).to have_attributes(email: email, admin: true, super_admin: false)
      expect(owner.authenticate(password)).to eq(owner)
      expect(owner.store).to have_attributes(storefront_enabled: false, subscription_required: true,
        billing_status: "canceled")
      follow_redirect!
      expect(response).to have_http_status(:ok)
      expect do
        post signup_confirm_path, params: { token: token, password: password, password_confirmation: password }
      end.to change(Store, :count).by(0).and change(User, :count).by(0)
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "rejects invalid and expired verification links without provisioning" do
      registration = pending_registration
      token = registration.verification_token
      travel 25.hours do
        expect do
          post signup_confirm_path, params: { token: token, password: password, password_confirmation: password }
        end.to change(Store, :count).by(0).and change(User, :count).by(0)
        expect(response).to have_http_status(:unprocessable_entity)
        get "/signup/verify", params: { token: "invalid-token" }
        expect(response).to have_http_status(:unprocessable_entity)
      end
      expect(registration.reload).not_to be_verified
    end

    it "rejects invalid confirmation passwords without provisioning or consuming the email link" do
      registration = pending_registration
      token = registration.verification_token
      [ { password: "short", password_confirmation: "short" },
        { password: password, password_confirmation: "does-not-match" },
        { password: "x" * 73, password_confirmation: "x" * 73 } ].each do |invalid|
        expect do
          post signup_confirm_path, params: { token: token }.merge(invalid)
        end.to change(Store, :count).by(0).and change(User, :count).by(0)
        expect(response).to have_http_status(:unprocessable_entity)
        expect(registration.reload).not_to be_verified
        expect(registration.password_digest).to be_nil
        expect(Registration.find_by_token_for(:email_verification, token)).to eq(registration)
        expect(document.css("input[type='password']").all? { |field| field["value"].blank? }).to be(true)
      end
    end

    it "rotates verification links after the resend cooldown and hides unknown addresses" do
      registration = pending_registration
      old_token = registration.verification_token
      post "/signup/resend", params: { email: email }
      expect(response).to redirect_to(%r{/signup/thanks})
      expect(enqueued_jobs).to be_empty
      expect(Registration.find_by_token_for(:email_verification, old_token)).to eq(registration)

      travel 3.minutes do
        post "/signup/resend", params: { email: " #{email.upcase} " }
        expect(response).to redirect_to(%r{/signup/thanks})
        expect(enqueued_jobs.count { |job| job[:job] == ActionMailer::MailDeliveryJob }).to eq(1)
        expect(Registration.find_by_token_for(:email_verification, old_token)).to be_nil
        expect(Registration.find_by_token_for(:email_verification, registration.reload.verification_token)).to eq(registration)
        post "/signup/resend", params: { email: "unknown-#{email}" }
        expect(response).to redirect_to(%r{/signup/thanks})
        expect(enqueued_jobs.count { |job| job[:job] == ActionMailer::MailDeliveryJob }).to eq(1)
      end
    end
  end

  context "with a verified unsubscribed account" do
    let!(:registration) { pending_registration }
    let!(:owner) { Registrations::Confirm.call(token: registration.verification_token, password: password, password_confirmation: password) }
    let(:store) { owner.store }

    before do
      post "/admin/login", params: { email: email, password: password }
      expect(response).to redirect_to(admin_root_path)
    end

    it "allows overview and subscription information but denies operational reads and writes" do
      get "/admin"
      expect(response).to have_http_status(:ok)
      get "/admin/subscription"
      expect(response).to have_http_status(:ok)
      get "/admin/products"
      expect(response).to redirect_to(admin_subscription_path)
      get "/admin/products", as: :json
      expect(response).to have_http_status(:payment_required)
      expect(response.parsed_body["error"]).to eq("subscription_required")
      expect do
        post "/admin/products", params: { product: { name: "Blocked", slug: "blocked" } }
      end.not_to change(Product, :count)
      expect(response).to redirect_to(admin_subscription_path)
    end

    it "does not let a selected workspace or foreign host bypass the subscription guard" do
      foreign = Store.create!(name: "Foreign", slug: "foreign-#{suffix}")
      get "/admin/products", params: { store_id: foreign.id, workspace: foreign.slug }
      expect(response).to redirect_to(admin_subscription_path)
      host! "#{foreign.slug}.#{Store.base_domain}"
      get "/admin/products"
      expect(response).to redirect_to(admin_login_path)
    end

    it "blocks authenticated API calls until subscription activation and when expired" do
      token = store.generate_api_token!
      headers = { "Authorization" => "Bearer #{token}" }
      post "/graphql", params: { query: "{ __typename }" }, headers: headers
      expect(response).to have_http_status(:payment_required)
      store.update!(billing_status: "active", billing_period_ends_on: Date.current + 1.month)
      post "/graphql", params: { query: "{ __typename }" }, headers: headers
      expect(response).to have_http_status(:ok)
      store.update!(billing_period_ends_on: Date.yesterday)
      post "/graphql", params: { query: "{ __typename }" }, headers: headers
      expect(response).to have_http_status(:payment_required)
    end

    it "allows subscribed operations and keeps legacy workspaces unchanged" do
      store.update!(billing_status: "active", billing_period_ends_on: Date.current + 1.month)
      get "/admin/products"
      expect(response).to have_http_status(:ok)
      store.update!(billing_status: "canceled", subscription_required: false)
      get "/admin/products"
      expect(response).to have_http_status(:ok)
    end
  end
end
