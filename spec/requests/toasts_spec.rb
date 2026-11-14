require "rails_helper"
require "nokogiri"

# Notices are floating windows that go away by themselves, not banners that push the page down.
RSpec.describe "Notices as toasts", type: :request do
  let(:password) { "synthetic-password-123" }
  let(:store) { Store.create!(slug: "ts-#{SecureRandom.hex(5)}", name: "Walkfit", currency: "MAD") }
  let!(:owner) { store.users.create!(name: "Owner", email: "owner-#{SecureRandom.hex(4)}@example.test", password: password, admin: true) }
  let!(:saida) { store.users.create!(name: "Saida", email: "saida-#{SecureRandom.hex(4)}@example.test", password: password, admin: false, confirmation_role: "agent") }

  def sign_in(user)
    host! "#{store.slug}.#{Store.base_domain}"
    post "/admin/login", params: { email: user.email, password: password }
  end

  def page = Nokogiri::HTML(response.body)

  it "shows a notice for two seconds in a window, and an error for four" do
    sign_in(owner)
    patch permissions_admin_user_path(saida), params: { areas: %w[dashboard queue] }
    follow_redirect!
    toast = page.at_css("[data-toasts] [data-toast-kind=notice]")
    expect(toast.text).to include("Saida")
    expect(toast["data-controller"]).to eq("toast")
    expect(toast["data-toast-duration-value"]).to eq("2000")
    expect(toast["class"]).to include("toast-overlay")
    expect(toast.at_css(".toast-card")).to be_present # the welcome-window look: a glass card
    expect(page.at_css("[data-toasts]")["class"]).to include("fixed")
    expect(page.at_css("[data-toasts]")).to have_attributes(attributes: include("data-turbo-temporary"))

    patch permissions_admin_user_path(owner), params: { areas: %w[dashboard] } # not allowed on yourself: an error
    follow_redirect!
    alert = page.at_css("[data-toasts] [data-toast-kind=alert]")
    expect(alert["data-toast-duration-value"]).to eq("4000")
    expect(alert["role"]).to eq("alert")
  end

  it "shows nothing when there is no notice, and no old banner" do
    sign_in(owner)
    get admin_users_path # the sign-in notice shows here, once
    expect(page.at_css("[data-toasts] [data-toast-kind=notice]").text).to include("Bienvenue")
    get admin_users_path
    expect(page.at_css("[data-toasts]")).to be_nil
  end
end
