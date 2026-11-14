require "rails_helper"
require "nokogiri"

RSpec.describe "Call center menu", type: :request do
  let(:password) { "synthetic-password-123" }
  let(:store) { Store.create!(slug: "cm-#{SecureRandom.hex(5)}", name: "Walkfit", currency: "MAD") }
  let(:owner) { store.users.create!(name: "Owner", email: "owner-#{SecureRandom.hex(4)}@example.test", password: password, admin: true) }
  let(:agent) { store.users.create!(name: "Saida", email: "saida-#{SecureRandom.hex(4)}@example.test", password: password, admin: false, confirmation_role: "agent") }

  def sign_in(user)
    host! "#{store.slug}.#{Store.base_domain}"
    post "/admin/login", params: { email: user.email, password: password }
  end

  def menu = Nokogiri::HTML(response.body).at_css("[data-call-center-nav]")
  def items = menu.css("[data-subnav-item]").to_h { |item| [ item["data-subnav-item"], item ] }

  it "replaces Confirmation by a Centre d'appels group with its six pages for the owner" do
    sign_in(owner)
    get "/dashboard"

    expect(menu.at_css("summary").text.squish).to eq("Centre d'appels")
    expect(items.keys).to eq(%w[queue analytics assignments rules attendance billing])
    expect(items["queue"]["href"]).to eq("/confirmation")
    expect(items["analytics"]["href"]).to eq("/admin/confirmations/analytics")
    expect(items["assignments"]["href"]).to eq("/admin/confirmations/assignments")
    expect(items["rules"]["href"]).to eq("/admin/confirmations/rules")
    expect(items["attendance"]["href"]).to eq("/admin/confirmations/attendance")
    expect(items["billing"]["href"]).to eq("/admin/agent-billing")
    expect(menu.has_attribute?("open")).to be(false)                           # closed away from the call center
  end

  it "is open on the call center pages, with the current page marked" do
    sign_in(owner)
    get "/admin/confirmations/center"
    expect(menu.has_attribute?("open")).to be(true)
    expect(items["queue"]["aria-current"]).to eq("page")

    get "/admin/confirmations/dashboard"
    expect(items["analytics"]["aria-current"]).to eq("page")
    expect(items["queue"]["aria-current"]).to be_nil
  end

  it "gives an agent only the queue and the analytics" do
    sign_in(agent)
    get "/admin/confirmations/center"

    expect(items.keys).to eq(%w[queue analytics])
  end

  it "opens the same new-order window from the queue page as the Orders page does" do
    sign_in(owner)
    get "/admin/confirmations/center"

    page = Nokogiri::HTML(response.body)
    expect(page.at_css("turbo-frame#order-modal")).to be_present
    expect(page.at_css("a[href='/admin/orders/new'][data-turbo-frame='order-modal']")).to be_present
  end

  it "puts the date picker in the dark header, before the agent's name, and not in the filters row" do
    sign_in(agent)
    get "/admin/confirmations/center"

    page = Nokogiri::HTML(response.body)
    header = page.at_css("[data-cc-header]")
    expect(header.at_css("[data-controller~='date-range-picker']")).to be_present
    expect(page.at_css("[data-cc-filters] [data-controller~='date-range-picker']")).to be_nil
    expect(header.at_css("[data-controller~='date-range-picker']").xpath("following::span[contains(@class,'rounded-full')]").map(&:text).join).to include("Saida")
  end
end
