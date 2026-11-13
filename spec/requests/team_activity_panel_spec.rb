require "rails_helper"
require "nokogiri"

# The "Activité de l'équipe" panel in the Utilisateurs tab.
RSpec.describe "Team activity panel", type: :request do
  let(:password) { "synthetic-password-123" }
  let(:store) { Store.create!(slug: "tp-#{SecureRandom.hex(5)}", name: "Walkfit", currency: "MAD") }
  let!(:owner) { store.users.create!(name: "Moubarak Amqor", email: "owner-#{SecureRandom.hex(4)}@example.test", password: password, admin: true) }
  let!(:saida) { store.users.create!(name: "saida confirmation", email: "saida-#{SecureRandom.hex(4)}@example.test", password: password, admin: false, confirmation_role: "agent") }
  let!(:yasmine) { store.users.create!(name: "Yasmine Confirmatrice", email: "yas-#{SecureRandom.hex(4)}@example.test", password: password, admin: false, confirmation_role: "agent") }

  def sign_in(user)
    host! "#{store.slug}.#{Store.base_domain}"
    post "/admin/login", params: { email: user.email, password: password }
  end

  def page = Nokogiri::HTML(response.body)

  before do
    ConfirmationShift.create!(store: store, user: saida, started_at: 90.minutes.ago, last_seen_at: 20.seconds.ago)
  end

  it "shows presence, time worked and what each person did, with gold and green role chips" do
    sign_in(owner)
    get admin_users_path
    expect(response).to have_http_status(:ok)
    panel = page.at_css("[data-team-activity]")
    expect(panel.at_css("[data-live-dot] .animate-ping")).to be_present # the live indicator is a blinking dot
    expect(panel.at_css("[data-kpi=presence] [data-value]").text.squish).to eq("1")
    expect(panel.at_css("[data-kpi=presence]").text).to include("3")
    expect(panel.at_css("[data-kpi=worked] [data-value]").text).to match(/1 h|\d+ min/)

    rows = panel.css("[data-activity-row]").to_h { |row| [ row["data-activity-row"].to_i, row ] }
    expect(rows.keys).to contain_exactly(owner.id, saida.id, yasmine.id)
    expect(rows[saida.id]["data-online"]).to eq("true")
    expect(rows[yasmine.id]["data-online"]).to eq("false")
    expect(panel.css("[data-activity-row]").first["data-activity-row"].to_i).to eq(saida.id) # online first
    expect(rows[owner.id].at_css("span[class*='from-[#f7d9a4]']")).to be_present   # owner chip: gold
    expect(rows[saida.id].at_css("span[class*='bg-[#d9f2e2]']")).to be_present     # agent chip: green
  end

  it "filters the panel by status, role and name, and keeps the members table" do
    sign_in(owner)
    get admin_users_path, params: { presence: "online" }
    expect(page.css("[data-activity-row]").map { |row| row["data-activity-row"].to_i }).to eq([ saida.id ])
    get admin_users_path, params: { role: "owner" }
    expect(page.css("[data-activity-row]").map { |row| row["data-activity-row"].to_i }).to eq([ owner.id ])
    get admin_users_path, params: { aq: "yasmine" }
    expect(page.css("[data-activity-row]").map { |row| row["data-activity-row"].to_i }).to eq([ yasmine.id ])
    get admin_users_path, params: { aq: "personne-ne-s-appelle-ainsi" }
    expect(page.at_css("[data-no-activity]")).to be_present
    expect(page.css("[data-member]").size).to eq(3) # the members table is separate
  end
end
