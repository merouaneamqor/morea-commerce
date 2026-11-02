# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Platform OAuth grants", type: :model do
  let!(:owner) { User.create!(email: "oauth-platform@example.test", password: "synthetic-credential-123", super_admin: true, admin: true) }
  let(:resource) { "https://platform.example.test/platform/mcp" }
  let(:verifier) { "v" * 43 }
  let(:challenge) { Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false) }
  let(:exchange_args) { { client_id: "client-one", redirect_uri: "https://client.example.test/callback", code_verifier: verifier, resource: resource } }

  def issue_code
    PlatformOauthCode.issue!(user: owner, client_id: exchange_args[:client_id],
      redirect_uri: exchange_args[:redirect_uri], code_challenge: challenge, resource: resource)
  end

  it "exchanges a bound S256 code once and stores only credential digests" do
    code = issue_code
    access, refresh = PlatformOauthCode.exchange!(code: code, **exchange_args)
    grant = PlatformOauthToken.authenticate(access)
    expect(grant.user).to eq(owner)
    expect(grant.resource).to eq(resource)
    expect(grant.token_digest).not_to eq(access)
    expect(grant.refresh_digest).not_to eq(refresh)
    expect(PlatformOauthCode.first.code_digest).not_to eq(code)
    expect(PlatformOauthCode.exchange!(code: code, **exchange_args)).to be_nil
    expect(OauthAccessToken.authenticate(access)).to be_nil
  end

  it "rejects mismatched clients, redirects, resources and invalid PKCE" do
    code = issue_code
    [ { client_id: "other" }, { redirect_uri: "https://evil.example.test" },
      { resource: "https://platform.example.test/mcp" }, { resource: "" },
      { code_verifier: "wrong" * 10 }, { code_verifier: "short" } ].each do |override|
      expect(PlatformOauthCode.exchange!(code: code, **exchange_args.merge(override))).to be_nil
    end
    expect(PlatformOauthCode.exchange!(code: code, **exchange_args.except(:resource))).to be_present
  end

  it "expires codes and refuses suspended or demoted owners" do
    code = issue_code
    travel_to(PlatformOauthCode.first.expires_at, with_usec: true) do
      expect(PlatformOauthCode.exchange!(code: code, **exchange_args)).to be_nil
    end
    owner.update!(status: "suspended")
    expect(PlatformOauthCode.exchange!(code: code, **exchange_args)).to be_nil
    expect { issue_code }.to raise_error(ArgumentError)
    owner.update_columns(status: "active", super_admin: false)
    expect(PlatformOauthCode.exchange!(code: code, **exchange_args)).to be_nil
  end

  it "binds refresh tokens to clients and resources and rotates them only once" do
    access, refresh = PlatformOauthToken.issue!(user: owner, client_id: "client-one", resource: resource)
    expect(PlatformOauthToken.rotate!(refresh, client_id: "other", resource: resource)).to be_nil
    expect(PlatformOauthToken.rotate!(refresh, client_id: "client-one", resource: "wrong")).to be_nil
    replacement = PlatformOauthToken.rotate!(refresh, client_id: "client-one", resource: resource)
    expect(replacement).to be_present
    expect(PlatformOauthToken.authenticate(access)).to be_nil
    expect(PlatformOauthToken.rotate!(refresh, client_id: "client-one", resource: resource)).to be_nil
    expect(PlatformOauthToken.authenticate(replacement.first)).to be_present
  end

  it "enforces access and refresh expiry and revocation" do
    access, refresh = PlatformOauthToken.issue!(user: owner, client_id: "client-one", resource: resource)
    grant = PlatformOauthToken.authenticate(access)
    travel_to(grant.expires_at, with_usec: true) { expect(PlatformOauthToken.authenticate(access)).to be_nil }
    travel_to(grant.refresh_expires_at, with_usec: true) do
      expect(PlatformOauthToken.rotate!(refresh, client_id: "client-one")).to be_nil
    end
    owner.update!(status: "suspended")
    expect(PlatformOauthToken.authenticate(access)).to be_nil
    expect(PlatformOauthToken.rotate!(refresh, client_id: "client-one")).to be_nil
    owner.update!(status: "active")
    grant.update!(revoked_at: Time.current)
    expect(PlatformOauthToken.authenticate(access)).to be_nil
    expect(PlatformOauthToken.rotate!(refresh, client_id: "client-one")).to be_nil
  end
end
