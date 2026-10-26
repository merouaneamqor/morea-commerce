require "rails_helper"

RSpec.describe "Confirmation reminders", type: :request do
  let(:password) { "synthetic-password-123" }
  let(:store) { Store.create!(slug: "remind-#{SecureRandom.hex(5)}", name: "Synthetic desk", currency: "MAD") }
  let(:vapid) { { subject: "mailto:test@example.test", public_key: "public-key", private_key: "private-key" } }
  let(:admin) { store.users.create!(name: "Ana", email: "admin-#{SecureRandom.hex(5)}@example.test", password: password, admin: true) }
  let(:agent) { store.users.create!(name: "Lina", email: "agent-#{SecureRandom.hex(5)}@example.test", password: password, admin: false, confirmation_role: "agent") }

  def subscribe(user)
    PushSubscription.create!(store: store, user: user, endpoint: "https://push.example.test/#{SecureRandom.hex(8)}", p256dh: "p", auth: "a")
  end

  def sign_in(user)
    host! "#{store.slug}.#{Store.base_domain}"
    post "/admin/login", params: { email: user.email, password: password }
    expect(response).to have_http_status(:redirect)
  end

  before do
    allow(Rails.configuration.x).to receive(:web_push).and_return(vapid)
    allow(WebPush).to receive(:payload_send)
  end

  it "sends the reminder to agents only" do
    subscribe(agent)
    subscribe(admin)
    sign_in(admin)

    post "/admin/confirmations/remind", params: { message: "  Work the queue now  " }

    expect(response).to redirect_to("/admin/confirmations")
    expect(WebPush).to have_received(:payload_send).once do |args|
      expect(args[:endpoint]).to eq(PushSubscription.joins(:user).find_by!(user: agent).endpoint)
      expect(JSON.parse(args[:message])).to include("kind" => "reminder", "body" => "Work the queue now")
    end
  end

  it "uses the default text when no message is given" do
    subscribe(agent)
    sign_in(admin)

    post "/admin/confirmations/remind"

    expect(WebPush).to have_received(:payload_send).once do |args|
      expect(JSON.parse(args[:message])["body"]).to eq(I18n.t("admin.confirmations.remind_default", locale: :fr))
    end
  end

  it "refuses agents, who are not admins" do
    subscribe(agent)
    sign_in(agent)

    post "/admin/confirmations/remind"

    expect(response).to have_http_status(:forbidden)
    expect(WebPush).not_to have_received(:payload_send)
  end

  it "does not send a second reminder within the cooldown" do
    subscribe(agent)
    sign_in(admin)
    allow(Rails.cache).to receive(:write).and_return(false)

    post "/admin/confirmations/remind"

    expect(response).to redirect_to("/admin/confirmations")
    expect(WebPush).not_to have_received(:payload_send)
  end

  it "says so when no agent can receive it, and allows an immediate retry" do
    sign_in(admin)
    expect(Rails.cache).to receive(:delete).with("confirmation-reminder/#{store.id}")

    post "/admin/confirmations/remind"

    expect(flash[:alert]).to eq(I18n.t("admin.confirmations.remind_none", locale: :fr))
  end

  it "caps the message at 120 characters" do
    subscribe(agent)
    sign_in(admin)

    post "/admin/confirmations/remind", params: { message: "x" * 300 }

    expect(WebPush).to have_received(:payload_send).once do |args|
      expect(JSON.parse(args[:message])["body"].length).to eq(120)
    end
  end
end
