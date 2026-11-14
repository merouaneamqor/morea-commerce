require "rails_helper"
require "nokogiri"

# The Équipe page: header bar, Utilisateurs / Rôles tabs, four figure cards, and the members table with search, status, who created each account and actions.
RSpec.describe "Team page", type: :request do
  let(:password) { "synthetic-password-123" }
  let(:store) { Store.create!(slug: "tm-#{SecureRandom.hex(5)}", name: "Walkfit", currency: "MAD") }
  let!(:owner) { store.users.create!(name: "Moubarak Amqor", email: "owner-#{SecureRandom.hex(4)}@example.test", password: password, admin: true) }
  let!(:saida) { store.users.create!(name: "saida confirmation", email: "saida-#{SecureRandom.hex(4)}@example.test", password: password, admin: false, confirmation_role: "agent", pay_per_delivery_cents: 800, created_by: owner) }
  let!(:yasmine) { store.users.create!(name: "Yasmine Confirmatrice", email: "yas-#{SecureRandom.hex(4)}@example.test", password: password, admin: false, confirmation_role: "agent", status: "suspended") }

  def sign_in(user)
    host! "#{store.slug}.#{Store.base_domain}"
    post "/admin/login", params: { email: user.email, password: password }
  end

  def page = Nokogiri::HTML(response.body)

  it "shows the four figures, the members with their role, status and who created them, and the actions" do
    sign_in(owner)
    get admin_users_path
    expect(response).to have_http_status(:ok)
    expect(page.at_css("[data-team-header]").text).to include("Gestion de l'équipe")
    expect(page.at_css("[data-tab='users']").text).to include("(3)")
    expect(page.css("[data-kpis=team] [data-kpi]").to_h { |kpi| [ kpi["data-kpi"], kpi.at_css("[data-value]").text.squish ] }).to eq("total" => "3", "active" => "2", "inactive" => "1", "owners" => "1")

    rows = page.css("[data-member]").to_h { |row| [ row["data-member"].to_i, row ] }
    expect(rows.keys).to contain_exactly(owner.id, saida.id, yasmine.id)
    expect(rows[owner.id].text).to include(I18n.t("admin.team.you"), I18n.t("admin.team.owner"))
    expect(rows[saida.id].text).to include("Moubarak Amqor", "Agent", "Actif", "1 boutique")
    expect(rows[yasmine.id].text).to include("Suspendu", "Système")
    expect(page.at_css("[data-add-user]")["href"]).to eq(new_admin_user_path)
    expect(rows[owner.id].at_css("form[action='#{admin_user_path(owner)}'] input[name=_method][value=delete]")).to be_nil # you cannot remove yourself
    expect(rows[saida.id].at_css("form[action='#{admin_user_path(saida)}'] input[name=_method][value=delete]")).to be_present
  end

  it "searches the members by name or email, and lists the roles with how many people have each" do
    sign_in(owner)
    get admin_users_path, params: { q: "yasmine" }
    expect(page.css("[data-member]").map { |row| row["data-member"].to_i }).to eq([ yasmine.id ])
    get admin_users_path, params: { q: "personne-ne-s-appelle-ainsi" }
    expect(page.at_css("[data-no-members]")).to be_present
    expect(page.at_css("[data-tab='users']").text).to include("(3)") # the search never changes the totals

    get admin_users_path, params: { tab: "roles" }
    expect(page.css("[data-kpis=roles] [data-kpi]").to_h { |kpi| [ kpi["data-kpi"], kpi.at_css("[data-value]").text.squish ] }).to eq("roles_total" => "3", "roles_active" => "3", "roles_custom" => "0", "roles_system" => "3")
    counts = page.css("[data-team-roles] tr[data-role]").to_h { |role| [ role["data-role"], [ role.at_css("[data-role-count]").text.to_i, role.at_css("[data-permission-count]").text.to_i ] ] }
    expect(counts).to eq("super_admin" => [ 0, Team::Roles::AREAS.size ], "owner" => [ 1, Team::Roles::AREAS.count { |_, _, roles| roles.include?(:owner) } ], "agent" => [ 2, Team::Roles::AREAS.count { |_, _, roles| roles.include?(:agent) } ])
    expect(page.at_css("[data-create-role-soon]")).to be_present
    get admin_users_path, params: { tab: "roles", q: "confirmation" }
    expect(page.css("[data-team-roles] tr[data-role]").map { |row| row["data-role"] }).to eq([ "agent" ])
  end

  it "shows what each user can open, by role, and nothing for nobody" do
    sign_in(owner)
    get admin_users_path, params: { tab: "permissions" }
    expect(page.css("#permission-user option").size).to eq(4)
    expect(page.at_css("[data-permission-list]")).to be_nil

    get admin_users_path, params: { tab: "permissions", user_id: saida.id }
    granted = page.css("[data-permissions-form-edit] input[name='areas[]']").select { |box| box["checked"] }.map { |box| box["value"] }
    expect(granted).to contain_exactly(*Team::Roles::AREAS.select { |_, _, roles| roles.include?(:agent) }.map(&:first))
    expect(page.at_css("[data-permissions-form-edit] input[value=accounting]")).to be_nil # the agent role does not have it

    get admin_users_path, params: { tab: "permissions", user_id: owner.id }
    expect(page.at_css("[data-area=agent_billing]")["data-granted"]).to eq("true") # your own permissions are shown, read-only
    expect(page.at_css("[data-area=own_billing]")["data-granted"]).to eq("false") # the agent-only entry is not the owner's
  end

  it "records who created an account" do
    sign_in(owner)
    post admin_users_path, params: { user: { email: "new-#{SecureRandom.hex(3)}@example.test", name: "Nouvelle Agente", confirmation_role: "agent", password: password, password_confirmation: password, pay_per_delivery: "8" } }
    expect(store.users.find_by(name: "Nouvelle Agente").created_by).to eq(owner)
  end

  it "stays closed to agents and renders in every language without a missing translation" do
    sign_in(owner)
    SellerHelper.untranslated.clear
    %w[fr en es ar].each do |locale|
      %w[users roles permissions].each do |tab|
        get admin_users_path, params: { locale: locale, tab: tab, user_id: saida.id }
        expect(response).to have_http_status(:ok)
        expect(response.body).not_to match(/translation[ _]missing/i)
      end
    end
    expect(SellerHelper.untranslated.to_a).to eq([])

    delete admin_logout_path rescue nil
    sign_in(saida)
    get admin_users_path
    expect(response).to redirect_to(admin_my_stats_path)
  end
end
