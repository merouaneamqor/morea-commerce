require "rails_helper"
require "nokogiri"

# The owner's WhatsApp settings page.
RSpec.describe "WhatsApp settings", type: :request do
  let(:password) { "synthetic-password-123" }
  let(:store) { Store.create!(slug: "ws-#{SecureRandom.hex(5)}", name: "Walkfit", currency: "MAD") }
  let!(:owner) { store.users.create!(name: "Owner", email: "owner-#{SecureRandom.hex(4)}@example.test", password: password, admin: true) }
  let!(:agent) { store.users.create!(name: "Saida", email: "saida-#{SecureRandom.hex(4)}@example.test", password: password, admin: false, confirmation_role: "agent") }
  let(:params) { { whatsapp_account: { name: "Walkfit", display_phone: "+212 600-000000", phone_number_id: "1318994621304711", business_account_id: "1119867737576759", access_token: "EAAG-secret-1234" } } }
  let(:reply) { Struct.new(:code, :body) }

  def sign_in(user)
    host! "#{store.slug}.#{Store.base_domain}"
    post "/admin/login", params: { email: user.email, password: password }
  end

  def page = Nokogiri::HTML(response.body)

  it "lets the owner connect a number by hand, never shows the token back, and shows the queue link" do
    sign_in(owner)
    get admin_whatsapp_path
    expect(response).to have_http_status(:ok)
    expect(page.at_css("[data-no-accounts]")).to be_present

    post admin_whatsapp_accounts_path, params: params
    expect(response).to redirect_to(admin_whatsapp_path)
    account = store.whatsapp_accounts.last
    expect(account).to have_attributes(name: "Walkfit", phone_number_id: "1318994621304711", auto_send_new_orders: false)

    get admin_whatsapp_path
    card = page.at_css("[data-whatsapp-account='#{account.id}']")
    expect(card.at_css("[data-token-hint]").text).to eq("••••1234")
    expect(response.body).not_to include("EAAG-secret-1234")
    expect(card.at_css("textarea").text).to include("{{nom_client}}")
    expect(page.css("[data-keyword-insert-keyword-param]").size).to eq(Whatsapp::Keywords::KEYS.size)

    get center_admin_confirmations_path
    expect(page.at_css("[data-whatsapp-settings-link]")["href"]).to eq(admin_whatsapp_path)
  end

  it "saves the automatic message and the switch, keeps the token when none is typed, and refuses unknown keywords" do
    sign_in(owner)
    post admin_whatsapp_accounts_path, params: params
    account = store.whatsapp_accounts.last

    patch admin_whatsapp_account_path(account), params: { whatsapp_account: { auto_send_new_orders: "1", new_order_message: "Salam {{nom_client}}, commande {{numero_commande}} reçue.", access_token: "" } }
    expect(account.reload).to have_attributes(auto_send_new_orders: true, new_order_message: "Salam {{nom_client}}, commande {{numero_commande}} reçue.")
    expect(account.access_token).to eq("EAAG-secret-1234")

    patch admin_whatsapp_account_path(account), params: { whatsapp_account: { new_order_message: "Salam {{mot_inconnu}}" } }
    expect(flash[:alert]).to include("unknown keywords")
    expect(account.reload.new_order_message).to include("nom_client")

    patch admin_whatsapp_account_path(account), params: { whatsapp_account: { access_token: "EAAG-new-9999" } }
    expect(account.reload.token_hint).to eq("••••9999")
  end

  it "sends a test through the Cloud API and says whether it worked; the real network is never used" do
    sign_in(owner)
    post admin_whatsapp_accounts_path, params: params
    account = store.whatsapp_accounts.last
    allow_any_instance_of(Whatsapp::CloudApi).to receive(:perform).and_return(reply.new("200", { messages: [ { id: "wamid.T1" } ] }.to_json))

    post admin_test_whatsapp_account_path(account), params: { to: "06 12 34 56 78" }
    expect(flash[:notice]).to be_present
    expect(WhatsappMessage.last).to have_attributes(kind: "test", status: "sent", to_phone: "212612345678")

    allow_any_instance_of(Whatsapp::CloudApi).to receive(:perform).and_return(reply.new("400", { error: { message: "Token expired" } }.to_json))
    post admin_test_whatsapp_account_path(account), params: { to: "06 12 34 56 78" }
    expect(flash[:alert]).to include("Token expired")

    get admin_whatsapp_path
    expect(page.css("[data-whatsapp-message]").map { |row| row["data-status"] }).to contain_exactly("sent", "failed")
  end

  it "removes an account, and keeps agents and other stores out" do
    sign_in(owner)
    post admin_whatsapp_accounts_path, params: params
    account = store.whatsapp_accounts.last
    other = Store.create!(slug: "ot-#{SecureRandom.hex(5)}", name: "Other", currency: "MAD")
    foreign = other.whatsapp_accounts.create!(name: "Other", phone_number_id: "99999999", access_token: "tok")
    patch admin_whatsapp_account_path(foreign), params: { whatsapp_account: { active: "0" } }
    expect(response).to have_http_status(:not_found)
    expect(foreign.reload.active).to be(true)

    delete admin_whatsapp_account_path(account)
    expect(store.whatsapp_accounts.count).to eq(0)

    delete admin_logout_path rescue nil
    sign_in(agent)
    get admin_whatsapp_path
    expect(response).to redirect_to(admin_my_stats_path)
  end

  it "renders in every language without a missing translation" do
    sign_in(owner)
    post admin_whatsapp_accounts_path, params: params
    SellerHelper.untranslated.clear
    %w[fr en es ar].each do |locale|
      get admin_whatsapp_path, params: { locale: locale }
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to match(/translation[ _]missing/i)
    end
    expect(SellerHelper.untranslated.to_a).to eq([])
  end
end
