require "rails_helper"

RSpec.describe "Order alert subscriptions", type: :request do
  let(:password) { "synthetic-password-123" }
  let(:store) { Store.create!(slug: "push-#{SecureRandom.hex(5)}", name: "Synthetic desk", currency: "MAD") }
  let(:staff) { store.users.create!(email: "staff-#{SecureRandom.hex(5)}@example.test", password: password, admin: true) }
  let(:endpoint) { "https://push.example.test/#{SecureRandom.hex(8)}" }
  let(:json) { { "CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json" } }

  def sign_in(user = staff)
    host! "#{store.slug}.#{Store.base_domain}"
    post "/admin/login", params: { email: user.email, password: password }
    expect(response).to have_http_status(:redirect)
  end

  def subscription_body(url = endpoint)
    { subscription: { endpoint: url, keys: { p256dh: "p256dh-key", auth: "auth-secret" } } }.to_json
  end

  it "stores the browser subscription for the signed-in staff member" do
    sign_in

    post "/admin/push_subscription", params: subscription_body, headers: json

    expect(response).to have_http_status(:created)
    expect(PushSubscription.find_by!(endpoint: endpoint)).to have_attributes(store: store, user: staff, p256dh: "p256dh-key")
  end

  it "lets an agent subscribe without admin rights" do
    agent = store.users.create!(email: "agent-#{SecureRandom.hex(5)}@example.test", password: password, admin: false, confirmation_role: "agent")
    sign_in(agent)

    post "/admin/push_subscription", params: subscription_body, headers: json

    expect(response).to have_http_status(:created)
    expect(PushSubscription.find_by!(endpoint: endpoint).user).to eq(agent)
  end

  it "moves a browser to the user who signed in on it last" do
    other = store.users.create!(email: "other-#{SecureRandom.hex(5)}@example.test", password: password, admin: true)
    PushSubscription.create!(store: store, user: other, endpoint: endpoint, p256dh: "old", auth: "old")
    sign_in

    post "/admin/push_subscription", params: subscription_body, headers: json

    expect(PushSubscription.where(endpoint: endpoint).pluck(:user_id)).to eq([ staff.id ])
  end

  it "removes only the signed-in user's subscription" do
    PushSubscription.create!(store: store, user: staff, endpoint: endpoint, p256dh: "k", auth: "a")
    sign_in

    delete "/admin/push_subscription", params: { subscription: { endpoint: endpoint } }.to_json, headers: json

    expect(response).to have_http_status(:no_content)
    expect(PushSubscription.where(endpoint: endpoint)).to be_empty
  end

  it "rejects a non-https endpoint" do
    sign_in

    post "/admin/push_subscription", params: subscription_body("http://push.example.test/x"), headers: json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(PushSubscription.count).to eq(0)
  end

  it "serves a service worker that shows order notifications" do
    host! "#{store.slug}.#{Store.base_domain}"
    get "/admin/service-worker.js"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('addEventListener("push"', 'addEventListener("notificationclick"')
  end
end
