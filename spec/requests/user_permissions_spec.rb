require "rails_helper"
require "nokogiri"

# Per-user application permissions: the owner narrows what a person can open; the screen saves it and the app enforces it (pages, menu).
RSpec.describe "User permissions", type: :request do
  let(:password) { "synthetic-password-123" }
  let(:store) { Store.create!(slug: "up-#{SecureRandom.hex(5)}", name: "Walkfit", currency: "MAD") }
  let!(:owner) { store.users.create!(name: "Owner", email: "owner-#{SecureRandom.hex(4)}@example.test", password: password, admin: true) }
  let!(:second_owner) { store.users.create!(name: "Second", email: "second-#{SecureRandom.hex(4)}@example.test", password: password, admin: true) }
  let!(:saida) { store.users.create!(name: "Saida", email: "saida-#{SecureRandom.hex(4)}@example.test", password: password, admin: false, confirmation_role: "agent", pay_per_delivery_cents: 800) }

  def sign_in(user)
    host! "#{store.slug}.#{Store.base_domain}"
    post "/admin/login", params: { email: user.email, password: password }
  end

  def page = Nokogiri::HTML(response.body)

  def save(user, areas, **extra)
    patch permissions_admin_user_path(user), params: { areas: areas }.merge(extra)
  end

  describe User do
    it "gives what the role gives, and a custom list can only narrow it" do
      expect(saida.allowed_areas).to match_array(Team::Roles.find(:agent).areas)
      saida.update!(custom_permissions: %w[dashboard queue])
      expect(saida.allowed_areas).to eq(%w[dashboard queue])
      expect(saida.area_allowed?("analytics")).to be(false)

      saida.custom_permissions = %w[dashboard accounting] # accounting is not an agent area
      expect(saida).not_to be_valid
      expect(owner.allowed_areas).to match_array(Team::Roles.find(:owner).areas)
    end
  end

  it "saves the ticked areas, ignores what the role does not give, and 'all of the role' means no custom list" do
    sign_in(owner)
    save(saida, %w[dashboard queue clock_in accounting])
    expect(response).to redirect_to(admin_users_path(tab: "permissions", user_id: saida.id))
    expect(saida.reload.custom_permissions).to match_array(%w[dashboard queue clock_in])

    save(saida, Team::Roles.find(:agent).areas)
    expect(saida.reload.custom_permissions).to be_nil

    save(saida, %w[dashboard])
    patch permissions_admin_user_path(saida), params: { reset: "1" }
    expect(saida.reload.custom_permissions).to be_nil
  end

  it "closes the pages of an area to the person, hides them from the menu, and still lets them open the rest" do
    sign_in(owner)
    save(saida, %w[dashboard queue clock_in])
    delete admin_logout_path rescue nil
    sign_in(saida)

    get admin_my_stats_path
    expect(response).to have_http_status(:ok)
    menu_text = page.at_css("[data-sidebar-nav]").text
    expect(menu_text).not_to include("Facturation")
    expect(menu_text).not_to include("Analyses")
    expect(menu_text).to include("Centre d'appels")

    get center_admin_confirmations_path
    expect(response).to have_http_status(:ok)

    get analytics_admin_confirmations_path
    expect(response).to redirect_to(admin_my_stats_path)
    expect(flash[:alert]).to eq(I18n.t("admin.permissions.denied"))
    get admin_my_billing_path
    expect(response).to redirect_to(admin_my_stats_path)
    get new_admin_order_path
    expect(response).to redirect_to(admin_my_stats_path)
    post "/admin/orders", params: { order: { name: "Karim", phone: "0612345678", city: "Fès", address: "Rue 1" } }
    expect(Order.where(store: store).count).to eq(0)
  end

  it "sends someone who lost their landing page to another one, and says no when there is none" do
    sign_in(owner)
    save(saida, %w[queue])
    delete admin_logout_path rescue nil
    sign_in(saida)
    get admin_my_stats_path
    expect(response).to redirect_to(center_admin_confirmations_path)

    delete admin_logout_path rescue nil
    sign_in(owner)
    save(saida, [])
    delete admin_logout_path rescue nil
    sign_in(saida)
    get admin_my_stats_path
    expect(response).to have_http_status(:forbidden)
  end

  it "can close an area to another owner, but nobody can change their own permissions" do
    sign_in(owner)
    save(second_owner, %w[dashboard orders])
    expect(second_owner.reload.custom_permissions).to match_array(%w[dashboard orders])

    save(owner, %w[dashboard])
    expect(owner.reload.custom_permissions).to be_nil
    expect(flash[:alert]).to eq(I18n.t("admin.permissions.not_editable"))

    delete admin_logout_path rescue nil
    sign_in(second_owner)
    get admin_users_path
    expect(URI(response.location).path).to eq("/admin")
    get seller_accounting_path
    expect(URI(response.location).path).to eq("/admin")
    get admin_orders_path
    expect(response).to have_http_status(:ok)
  end

  it "does not let an agent change permissions, nor reach another store's people" do
    other = Store.create!(slug: "ot-#{SecureRandom.hex(5)}", name: "Other", currency: "MAD")
    foreign = other.users.create!(name: "Foreign", email: "f-#{SecureRandom.hex(4)}@example.test", password: password, admin: false, confirmation_role: "agent")
    sign_in(saida)
    save(saida, %w[dashboard queue])
    expect(saida.reload.custom_permissions).to be_nil
    delete admin_logout_path rescue nil
    sign_in(owner)
    save(foreign, %w[dashboard])
    expect(response).to have_http_status(:not_found)
    expect(foreign.reload.custom_permissions).to be_nil
  end

  it "shows the form with a card per application, the role's areas ticked, and a badge once customised" do
    sign_in(owner)
    get admin_users_path, params: { tab: "permissions", user_id: saida.id }
    form = page.at_css("[data-permissions-form-edit]")
    expect(form["action"]).to eq(permissions_admin_user_path(saida))
    expect(form.css("[data-group]").map { |card| card["data-group"] }).to eq(%w[dashboard orders call_center]) # only the applications the agent role has
    ticked = form.css("input[name='areas[]']").select { |box| box["checked"] }.map { |box| box["value"] }
    expect(ticked).to match_array(Team::Roles.find(:agent).areas)
    expect(page.at_css("[data-custom-badge]")).to be_nil
    expect(form.at_css("[data-save-permissions]")).to be_present
    expect(form.css("[data-card]").all? { |card| card.at_css("button[data-card-details]") && card.at_css("dialog[data-card-dialog] input[name='areas[]']") }).to be(true) # a title with an arrow, its areas in a small window
    expect(form.at_css("details")).to be_nil

    save(saida, %w[dashboard queue])
    get admin_users_path, params: { tab: "permissions", user_id: saida.id }
    expect(page.at_css("[data-custom-badge]")).to be_present
    expect(page.at_css("[data-reset]")).to be_present
    expect(page.css("[data-permission-groups] input[name='areas[]']").select { |box| box["checked"] }.map { |box| box["value"] }).to match_array(%w[dashboard queue])

    get admin_users_path, params: { tab: "permissions", user_id: owner.id }
    expect(page.at_css("[data-not-editable]")).to be_present # your own are read-only
    expect(page.at_css("[data-permissions-form-edit]")).to be_nil
  end
end
