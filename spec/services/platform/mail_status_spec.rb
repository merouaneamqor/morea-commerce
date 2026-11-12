# frozen_string_literal: true

require "rails_helper"

RSpec.describe Platform::MailStatus do
  around do |example|
    previous = ENV.to_hash.slice(*described_class::REQUIRED, *described_class::OPTIONAL)
    described_class::REQUIRED.each { |key| ENV.delete(key) }
    example.run
  ensure
    previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    (described_class::REQUIRED + described_class::OPTIONAL - previous.keys).each { |key| ENV.delete(key) }
  end

  it "reports missing required keys" do
    status = described_class.current
    expect(status.configured).to eq(false)
    expect(status.missing).to include("MAIL_FROM", "SMTP_ADDRESS", "SMTP_USERNAME", "SMTP_PASSWORD")
  end

  it "reports ready when required keys are set" do
    ENV["MAIL_FROM"] = "no-reply@seallo.ma"
    ENV["SMTP_ADDRESS"] = "smtp.resend.com"
    ENV["SMTP_USERNAME"] = "resend"
    ENV["SMTP_PASSWORD"] = "synthetic"
    status = described_class.current
    expect(status.configured).to eq(true)
    expect(status.missing).to be_empty
    expect(status.address).to eq("smtp.resend.com")
  end
end
