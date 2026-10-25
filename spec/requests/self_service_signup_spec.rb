# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Self-service merchant signup", type: :request do
  let(:suffix) { SecureRandom.hex(6) }
  let(:password) { "Synthetic-signup-#{suffix}" }
  let(:email) { "owner-#{suffix}@example.test" }
  let(:attributes) do
    { business_name: "Synthetic Workspace #{suffix}", email: email }
  end

  before { host! Store.base_domain }

  def register(**overrides)
    post "/signup", params: { registration: attributes.merge(overrides), locale: "en" }
  end

  def pending_registration
    Registration.create!(attributes.merge(locale: "en", verification_sent_at: Time.current))
  end

  def document
    Nokogiri::HTML(response.body)
  end

  it "creates an email-first registration and queues verification without provisioning" do
    expect do
      register(email: "  #{email.upcase}  ")
    end.to change(Registration, :count).by(1)
      .and change(Store, :count).by(0)
      .and change(User, :count).by(0)
      .and change(AccessRequest, :count).by(0)

    expect(response).to redirect_to(%r{/signup/thanks})
    registration = Registration.find_by!(email: email)
    expect(registration.password_digest).to be_nil
    expect(registration).not_to be_verified
    expect(enqueued_jobs.count { |job| job[:job] == ActionMailer::MailDeliveryJob }).to eq(1)
    get "/admin"
    expect(response).to redirect_to(admin_login_path)
  end

  %w[fr en ar].each do |locale|
    it "renders localized signup, verification and email instructions in #{locale}" do
      registration = pending_registration
      [ [ "/signup", {} ], [ "/signup/thanks", {} ],
        [ "/signup/verify", { token: registration.verification_token } ] ].each do |path, params|
        get path, params: params.merge(locale: locale)
        expect(response).to have_http_status(:ok)
        expect(document.at_css("html")["lang"]).to eq(locale)
        expect(response.body).not_to match(/translation missing/i)
        expect(document.css("input[type='password']")).to be_empty if path == "/signup"
      end
    end
  end

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

  it "cannot pre-register a victim with an attacker-chosen password" do
    attacker_password = "Attacker-password-123"
    register(password: attacker_password, password_confirmation: attacker_password)
    registration = Registration.find_by!(email: email)
    expect(registration.password_digest).to be_nil
    post "/admin/login", params: { email: email, password: attacker_password }
    expect(response).to have_http_status(:unprocessable_entity)
    post signup_confirm_path, params: { token: registration.verification_token,
      password: password, password_confirmation: password }
    expect(response).to redirect_to(admin_root_path(locale: I18n.locale))
    owner = registration.reload.user
    expect(owner.authenticate(password)).to eq(owner)
    expect(owner.authenticate(attacker_password)).to be(false)
  end

  it "responds generically to duplicate and existing account email addresses" do
    registration = pending_registration
    digest = registration.password_digest
    expect { register(password: "Different-password-123", password_confirmation: "Different-password-123") }
      .not_to change(Registration, :count)
    expect(response).to redirect_to(%r{/signup/thanks})
    expect(registration.reload.password_digest).to eq(digest)
    expect(enqueued_jobs).to be_empty

    workspace = Store.create!(name: "Existing", slug: "existing-#{suffix}")
    workspace.users.create!(email: "existing-#{email}", password: password, admin: true)
    expect { register(email: "existing-#{email}") }.not_to change(Registration, :count)
    expect(response).to redirect_to(%r{/signup/thanks})
  end

  it "validates malformed signup fields identically for known and unknown email addresses" do
    registration = pending_registration
    workspace = Store.create!(name: "Existing Identity", slug: "identity-#{suffix}")
    existing_user = workspace.users.create!(email: "existing-#{email}", password: password, admin: true)
    messages = [ registration.email, existing_user.email, "unknown-#{email}" ].map do |address|
      expect { register(email: address, business_name: "") }.not_to change(Registration, :count)
      expect(response).to have_http_status(:unprocessable_entity)
      errors = document.at_css('[role="alert"]').text.squish
      expect(errors).not_to match(/taken|already|registered|used/i)
      errors
    end
    expect(messages.uniq.size).to eq(1)
    expect(enqueued_jobs).to be_empty
  end

  it "limits signup and resend attempts by IP without provisioning accounts" do
    memory_store = ActiveSupport::Cache::MemoryStore.new
    # Rails captures the configured cache instance when declaring rate_limit.
    # Give that captured instance real in-memory counters for this test only.
    allow(SignupsController.cache_store).to receive(:increment) do |*args, **options|
      memory_store.increment(*args, **options)
    end
    headers = { "REMOTE_ADDR" => "203.0.113.51" }
    expect do
      5.times do
        post "/signup", params: { registration: attributes, website: "https://bot.example.test" }, headers: headers
        expect(response).to have_http_status(:redirect)
        post signup_resend_path, params: { email: "unknown-#{email}" }, headers: headers
        expect(response).to have_http_status(:redirect)
      end
      post "/signup", params: { registration: attributes }, headers: headers
      expect(response).to have_http_status(:too_many_requests)
      post signup_resend_path, params: { email: "unknown-#{email}" }, headers: headers
      expect(response).to have_http_status(:too_many_requests)
      post "/signup", params: { registration: attributes, website: "https://bot.example.test" },
        headers: { "REMOTE_ADDR" => "203.0.113.52" }
      expect(response).to have_http_status(:redirect)
    end.to change(Registration, :count).by(0)
      .and change(Store, :count).by(0)
      .and change(User, :count).by(0)
    expect(enqueued_jobs).to be_empty
  end

  it "ignores the honeypot without creating an identity or sending a message" do
    expect do
      post "/signup", params: { registration: attributes, website: "https://bot.example.test" }
    end.not_to change(Registration, :count)
    expect(response).to redirect_to(%r{/signup/thanks})
    expect(enqueued_jobs).to be_empty
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

  it "refuses self-service signup on a tenant host" do
    store = Store.create!(name: "Tenant", slug: "tenant-#{suffix}")
    host! "#{store.slug}.#{Store.base_domain}"
    get "/signup"
    expect(response).to have_http_status(:not_found)
    expect { register }.not_to change(Registration, :count)
    expect(response).to have_http_status(:not_found)
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
