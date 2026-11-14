# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Confirmation presence endpoint", type: :request do
  let(:password) { "synthetic-password-123" }
  let(:store) { Store.create!(slug: "pres-#{SecureRandom.hex(4)}", name: "Presence HTTP", currency: "MAD") }
  let(:agent) do
    store.users.create!(name: "Agent", email: "agent-#{SecureRandom.hex(4)}@example.test",
      password: password, confirmation_role: "agent")
  end
  let(:owner) do
    store.users.create!(name: "Owner", email: "owner-#{SecureRandom.hex(4)}@example.test",
      password: password, admin: true)
  end

  def sign_in(user)
    host! "#{store.slug}.#{Store.base_domain}"
    post "/admin/login", params: { email: user.email, password: password }
    expect(response).to have_http_status(:redirect)
  end

  it "opens and closes an agent presence session over HTTP" do
    sign_in(agent)

    post "/admin/confirmations/presence"
    expect(response).to have_http_status(:no_content)
    expect(ConfirmationShift.open.where(store: store, user: agent).count).to eq(1)
    expect(Confirmations::Presence.new(store: store, user: agent).present?).to be(true)

    post "/admin/confirmations/presence", params: { away: "1" }
    expect(response).to have_http_status(:no_content)
    expect(ConfirmationShift.open.where(store: store, user: agent).count).to eq(0)
    expect(Confirmations::Presence.new(store: store, user: agent).present?).to be(false)
  end

  it "returns 204 for a manager without opening a shift" do
    sign_in(owner)

    post "/admin/confirmations/presence"
    expect(response).to have_http_status(:no_content)
    expect(ConfirmationShift.where(store: store).count).to eq(0)
  end

  it "requires a signed-in session" do
    host! "#{store.slug}.#{Store.base_domain}"
    post "/admin/confirmations/presence"
    expect(response).to have_http_status(:redirect)
    expect(ConfirmationShift.where(store: store).count).to eq(0)
  end
end
