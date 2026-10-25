# frozen_string_literal: true

require "rails_helper"
require "uri"

RSpec.describe "Onboarding emails", type: :mailer do
  let(:suffix) { SecureRandom.hex(6) }
  let(:trusted_origin) { "https://trusted-platform.example.test" }

  before do
    allow(Store).to receive(:platform_origin).and_return(trusted_origin)
  end

  def email_link(message, locale:, path:, translation_scope:)
    expect(message).to be_multipart
    expect(message.html_part).to be_present
    expect(message.text_part).to be_present
    html = message.html_part.body.decoded
    text = message.text_part.body.decoded
    expect(html).not_to match(/translation missing/i)
    expect(text).not_to match(/translation missing/i)
    expect(message.subject).to eq(I18n.t("#{translation_scope}.subject", locale: locale, name: Store.platform_name))
    expect(Nokogiri::HTML(html).text).to include(I18n.t("#{translation_scope}.expiry", locale: locale))
    expect(text).to include(I18n.t("#{translation_scope}.expiry", locale: locale))
    link = Nokogiri::HTML(html).at_css("a[href]")
    expect(link.text).to eq(I18n.t("#{translation_scope}.button", locale: locale))
    url = URI.parse(link["href"])
    expect("#{url.scheme}://#{url.host}").to eq(trusted_origin)
    expect(url.path).to eq(path)
    expect(text).to include(url.to_s)
    parameters = URI.decode_www_form(url.query).to_h
    expect(parameters.fetch("locale")).to eq(locale)
    parameters.fetch("token")
  end

  %w[fr en ar].each do |locale|
    it "renders a usable signed verification link in both parts for #{locale}, without sending" do
      registration = Registration.create!(business_name: "Email Workspace", email: "verify-#{locale}-#{suffix}@example.test", locale: locale)
      deliveries = ActionMailer::Base.deliveries.size
      message = RegistrationMailer.verification(registration).message
      expect(ActionMailer::Base.deliveries.size).to eq(deliveries)
      expect(message.to).to eq([ registration.email ])
      token = email_link(message, locale: locale, path: "/signup/verify", translation_scope: "registration_mailer")
      expect(Registration.find_by_token_for(:email_verification, token)).to eq(registration)
      travel 25.hours do
        expect(Registration.find_by_token_for(:email_verification, token)).to be_nil
      end
    end

    it "renders a usable short-lived password recovery link in both parts for #{locale}, without sending" do
      store = Store.create!(name: "Recovery Email Workspace", slug: "mailer-#{locale}-#{suffix}")
      user = store.users.create!(email: "reset-#{locale}-#{suffix}@example.test", password: "Synthetic-mailer-password-123", admin: true)
      deliveries = ActionMailer::Base.deliveries.size
      message = PasswordResetMailer.instructions(user, locale).message
      expect(ActionMailer::Base.deliveries.size).to eq(deliveries)
      expect(message.to).to eq([ user.email ])
      token = email_link(message, locale: locale, path: "/signup/password/edit", translation_scope: "password_reset_mailer")
      expect(User.find_by_token_for(:password_reset, token)).to eq(user)
      travel 16.minutes do
        expect(User.find_by_token_for(:password_reset, token)).to be_nil
      end
    end
  end
end
