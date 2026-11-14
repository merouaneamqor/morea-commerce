require "rails_helper"
require "nokogiri"

# The members table: a three-dots dropdown (Actions) and windows on the same page to see, edit, give a role, deactivate or remove a person.
RSpec.describe "Team member actions", type: :request do
  let(:password) { "synthetic-password-123" }
  let(:store) { Store.create!(slug: "mm-#{SecureRandom.hex(5)}", name: "Walkfit", currency: "MAD") }
  let!(:owner) { store.users.create!(name: "Moubarak Amqor", email: "owner-#{SecureRandom.hex(4)}@example.test", password: password, admin: true) }
  let!(:saida) { store.users.create!(name: "saida confirmation", email: "saida-#{SecureRandom.hex(4)}@example.test", password: password, admin: false, confirmation_role: "agent", pay_per_delivery_cents: 800, return_penalty_cents: 300, created_by: owner) }

  def sign_in(user, email_password: password)
    host! "#{store.slug}.#{Store.base_domain}"
    post "/admin/login", params: { email: user.email, password: email_password }
  end

  def page = Nokogiri::HTML(response.body)

  def row(user) = page.at_css("[data-member='#{user.id}']")

  it "has no buttons in the table cell but the three dots, a dropdown of actions, and the windows opened from it" do
    sign_in(owner)
    get admin_users_path
    cell = row(saida)
    expect(cell.at_css("td:last-child [data-member-menu]")).to be_present
    expect(cell.at_css("[popover][data-member-actions='#{saida.id}']")).to be_present

    menu = cell.at_css("[data-member-actions]")
    expect(menu.at_css("[data-menu-details]")).to be_present
    expect(menu.at_css("[data-menu-edit]")).to be_present
    expect(menu.at_css("[data-menu-role]")).to be_present
    expect(menu.at_css("a[data-menu-permissions]")["href"]).to eq(admin_users_path(tab: "permissions", user_id: saida.id))
    expect(menu.at_css("[data-menu-status]")["data-menu-status"]).to eq("deactivate")
    expect(menu.at_css("[data-menu-remove]")).to be_present

    details = cell.at_css("dialog[data-member-details='#{saida.id}']")
    expect(details.text.squish).to include("saida confirmation", saida.email, "Moubarak Amqor", "8 MAD", "3 MAD")
    expect(details.at_css("[data-open-edit]")).to be_present # Modifier opens the edit window
    expect(details.at_css("[data-details-status='deactivate']")).to be_present # and the account can be deactivated from here
    expect(details.at_css("[data-details-remove]")).to be_present

    edit = cell.at_css("dialog[data-member-edit='#{saida.id}']")
    expect(edit.at_css("form")["action"]).to eq(admin_user_path(saida))
    expect(edit.at_css("input[name='user[email]']")["value"]).to eq(saida.email)
    expect(edit.at_css("input[name='user[pay_per_delivery]']")["value"]).to eq("8")

    own = row(owner)
    expect(own.at_css("[data-menu-role], [data-menu-status], [data-menu-remove], dialog[data-member-role]")).to be_nil # nothing on yourself but details and edit
    expect(own.at_css("[data-menu-edit]")).to be_present
  end

  it "edits in place: the page stays the team page, a refused value comes back as a notice, and the password is kept when left empty" do
    sign_in(owner)
    patch admin_user_path(saida), params: { inline: "1", user: { name: "Saida Confirm", email: saida.email, password: "", pay_per_delivery: "9.5", return_penalty: "2" } }
    expect(URI(response.location).path).to eq("/admin/staff")
    expect(saida.reload).to have_attributes(name: "Saida Confirm", pay_per_delivery_cents: 950, return_penalty_cents: 200)
    expect(saida.authenticate(password)).to be_truthy

    patch admin_user_path(saida), params: { inline: "1", user: { name: "x", email: "" } }
    expect(URI(response.location).path).to eq("/admin/staff")
    expect(flash[:alert]).to be_present
    expect(saida.reload.email).not_to be_blank
  end

  it "gives a role in place, drops the custom permissions, and protects yourself, the last owner and super administrators" do
    saida.update!(custom_permissions: %w[dashboard queue])
    sign_in(owner)
    patch role_admin_user_path(saida), params: { role: "owner" }
    expect(saida.reload).to have_attributes(admin: true, custom_permissions: nil)
    expect(flash[:notice]).to eq(I18n.t("admin.team_actions.role_changed", name: saida.name))

    patch role_admin_user_path(saida), params: { role: "agent" }
    expect(saida.reload).to have_attributes(admin: false, confirmation_role: "agent")

    patch role_admin_user_path(saida), params: { role: "boss" }
    expect(flash[:alert]).to eq(I18n.t("admin.team_actions.unknown_role"))
    patch role_admin_user_path(owner), params: { role: "agent" }
    expect(flash[:alert]).to eq(I18n.t("admin.permissions.not_editable"))
    expect(owner.reload.admin).to be(true)
  end

  it "deactivates and reactivates an account: a deactivated person can no longer sign in" do
    sign_in(owner)
    patch status_admin_user_path(saida)
    expect(saida.reload.status).to eq("suspended")
    expect(flash[:notice]).to eq(I18n.t("admin.team_actions.deactivated", name: saida.name))
    get admin_users_path
    expect(row(saida).at_css("[data-menu-status]")["data-menu-status"]).to eq("reactivate")
    expect(row(saida).text).to include("Suspendu")

    delete admin_logout_path rescue nil
    sign_in(saida)
    get admin_my_stats_path
    expect(response).to redirect_to(%r{/admin/login})

    delete admin_logout_path rescue nil
    sign_in(owner)
    patch status_admin_user_path(saida)
    expect(saida.reload.status).to eq("active")
    patch status_admin_user_path(owner)
    expect(owner.reload.status).to eq("active") # not yourself
  end

  it "never lets the last active owner be demoted or deactivated, and keeps agents and other stores out" do
    other_owner = store.users.create!(name: "Second", email: "second-#{SecureRandom.hex(4)}@example.test", password: password, admin: true)
    sign_in(other_owner)
    patch status_admin_user_path(owner)
    expect(owner.reload.status).to eq("suspended") # allowed: another owner stays active
    patch status_admin_user_path(owner) # back to active
    expect(owner.reload.status).to eq("active")
    store.users.where(admin: true).where.not(id: [ owner.id ]).update_all(admin: false, confirmation_role: "agent")
    delete admin_logout_path rescue nil
    sign_in(owner)
    foreign_store = Store.create!(slug: "ot-#{SecureRandom.hex(5)}", name: "Other", currency: "MAD")
    foreign = foreign_store.users.create!(name: "Foreign", email: "f-#{SecureRandom.hex(4)}@example.test", password: password, admin: false, confirmation_role: "agent")
    patch status_admin_user_path(foreign)
    expect(response).to have_http_status(:not_found)

    delete admin_logout_path rescue nil
    sign_in(saida)
    patch status_admin_user_path(owner)
    expect(owner.reload.status).to eq("active")
  end

  it "keeps the black header above the content that follows, so the language menu is never hidden by the cards" do
    sign_in(owner)
    get admin_users_path
    expect(page.at_css("[data-team-header]")["class"]).to include("z-30")
    delete admin_logout_path rescue nil
    sign_in(saida)
    get admin_my_stats_path
    expect(page.at_css("[data-agent-header]")["class"]).to include("z-30")
  end
end
