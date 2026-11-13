# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Merchant password recovery", type: :request do
  let(:suffix) { SecureRandom.hex(6) }
  let(:old_password) { "Synthetic-original-#{suffix}" }
  let(:new_password) { "Synthetic-replacement-#{suffix}" }
  let(:store) { Store.create!(name: "Recovery Workspace", slug: "recovery-#{suffix}") }
  let(:user) { store.users.create!(email: "recover-#{suffix}@example.test", password: old_password, admin: true) }

  before { host! Store.base_domain }

  def reset_params(token, **overrides)
    { token: token, password: new_password, password_confirmation: new_password }.merge(overrides)
  end

  it "gives the same response for known and unknown email addresses" do
    post password_resets_path, params: { email: " #{user.email.upcase} ", locale: "en" }
    expect(response).to redirect_to(%r{/signup/password/new})
    expect(enqueued_jobs.count { |job| job[:job] == ActionMailer::MailDeliveryJob }).to eq(1)
    follow_redirect!
    known_response = Nokogiri::HTML(response.body).at_css('[role="status"]').text
    post password_resets_path, params: { email: "unknown-#{suffix}@example.test", locale: "en" }
    expect(response).to redirect_to(%r{/signup/password/new})
    expect(enqueued_jobs.count { |job| job[:job] == ActionMailer::MailDeliveryJob }).to eq(1)
    follow_redirect!
    expect(Nokogiri::HTML(response.body).at_css('[role="status"]').text).to eq(known_response)
  end

  it "does not choose arbitrarily between workspace accounts sharing an email" do
    other_store = Store.create!(name: "Other Recovery Workspace", slug: "other-recovery-#{suffix}")
    other_user = other_store.users.create!(email: user.email, password: old_password, admin: true)
    post password_resets_path, params: { email: user.email }
    expect(response).to redirect_to(%r{/signup/password/new})
    expect(enqueued_jobs).to be_empty
    post password_resets_path, params: { email: user.email, workspace: other_store.slug }
    expect(response).to redirect_to(%r{/signup/password/new})
    mail = enqueued_jobs.find { |job| job[:job] == ActionMailer::MailDeliveryJob }
    expect(mail).to be_present
    expect(mail[:args].to_json).to include("gid://", "User/#{other_user.id}")
  end

  it "never sends recovery messages for suspended accounts or pending registrations" do
    user.update!(status: "suspended")
    registration = Registration.create!(business_name: "Pending Recovery", email: "pending-#{suffix}@example.test",
      locale: "en")
    [ user.email, registration.email ].each do |email|
      post password_resets_path, params: { email: email }
      expect(response).to redirect_to(%r{/signup/password/new})
    end
    expect(enqueued_jobs).to be_empty
  end

  it "only displays the reset form on GET, without changing the password" do
    token = user.generate_token_for(:password_reset)
    digest = user.password_digest
    get edit_password_reset_path, params: { token: token }
    expect(response).to have_http_status(:ok)
    expect(user.reload.password_digest).to eq(digest)
    expect(response.headers["Cache-Control"]).to include("no-store")
    expect(response.headers["Referrer-Policy"]).to eq("no-referrer")
    expect(User.find_by_token_for(:password_reset, token)).to eq(user)
  end

  it "changes the password once, consumes the token and requires a fresh login" do
    token = user.generate_token_for(:password_reset)
    version = user.session_version
    patch password_reset_path, params: reset_params(token)
    expect(response).to redirect_to(admin_login_path(locale: I18n.locale))
    expect(user.reload.authenticate(new_password)).to eq(user)
    expect(user.authenticate(old_password)).to be(false)
    expect(user.session_version).to eq(version + 1)
    expect(User.find_by_token_for(:password_reset, token)).to be_nil
    patch password_reset_path, params: reset_params(token, password: "Replay-password-123", password_confirmation: "Replay-password-123")
    expect(response).to have_http_status(:unprocessable_entity)
    expect(user.reload.authenticate(new_password)).to eq(user)
    get "/admin"
    expect(response).to redirect_to(admin_login_path)
    post "/admin/login", params: { email: user.email, password: new_password }
    expect(response).to redirect_to(admin_root_path)
  end

  it "invalidates sessions created before recovery" do
    stale = ActionDispatch::Integration::Session.new(Rails.application)
    stale.host! Store.base_domain
    stale.post "/admin/login", params: { email: user.email, password: old_password }
    stale.get "/admin"
    expect(stale.response).to have_http_status(:ok)
    patch password_reset_path, params: reset_params(user.generate_token_for(:password_reset))
    expect(response).to have_http_status(:redirect)
    stale.get "/admin"
    expect(stale.response).to have_http_status(:redirect)
    expect(stale.response.location).to include("/admin/login")
  end

  it "rejects short, overlong and mismatched passwords without consuming the token" do
    token = user.generate_token_for(:password_reset)
    [ { password: "short", password_confirmation: "short" },
      { password_confirmation: "does-not-match" },
      { password: "x" * 73, password_confirmation: "x" * 73 } ].each do |invalid|
      patch password_reset_path, params: reset_params(token, **invalid)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(user.reload.authenticate(old_password)).to eq(user)
      expect(User.find_by_token_for(:password_reset, token)).to eq(user)
      expect(Nokogiri::HTML(response.body).css("input[type='password']").all? { |field| field["value"].blank? }).to be(true)
    end
  end

  it "rejects expired and invalid tokens and token reuse after suspension" do
    token = user.generate_token_for(:password_reset)
    travel 16.minutes do
      get edit_password_reset_path, params: { token: token }
      expect(response).to have_http_status(:unprocessable_entity)
      patch password_reset_path, params: reset_params(token)
      expect(response).to have_http_status(:unprocessable_entity)
    end
    user.update!(status: "suspended")
    patch password_reset_path, params: reset_params(token)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(user.reload.authenticate(old_password)).to eq(user)
    get edit_password_reset_path, params: { token: "invalid-token" }
    expect(response).to have_http_status(:unprocessable_entity)
  end

  %w[fr en ar].each do |locale|
    it "renders localized recovery pages in #{locale}" do
      get new_password_reset_path, params: { locale: locale }
      expect(response).to have_http_status(:ok)
      expect(Nokogiri::HTML(response.body).at_css("html")["lang"]).to eq(locale)
      get edit_password_reset_path, params: { token: user.generate_token_for(:password_reset), locale: locale }
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to match(/translation missing/i)
    end
  end

  it "does not expose recovery pages or accept recovery requests on tenant hosts" do
    host! "#{store.slug}.#{Store.base_domain}"
    get new_password_reset_path
    expect(response).to have_http_status(:not_found)
    post password_resets_path, params: { email: user.email }
    expect(response).to have_http_status(:not_found)
    expect(enqueued_jobs).to be_empty
  end
end
