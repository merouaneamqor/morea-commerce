require "rails_helper"

RSpec.describe "Store manager menu", type: :request do
  let(:password) { "synthetic-password-123" }
  let(:store) { Store.create!(slug: "menu-#{SecureRandom.hex(5)}", name: "Synthetic workspace", currency: "MAD") }
  let(:staff) { store.users.create!(email: "menu-#{SecureRandom.hex(5)}@example.test", password: password, admin: true) }

  def sign_in(user = staff, workspace: store)
    host! workspace ? "#{workspace.slug}.#{Store.base_domain}" : Store.base_domain
    post "/admin/login", params: { email: user.email, password: password }
    expect(response).to have_http_status(:redirect)
  end

  it "requires authentication for placeholder pages" do
    host! "#{store.slug}.#{Store.base_domain}"
    get "/admin/expenses"
    expect(response).to redirect_to(admin_login_path)
  end

  it "renders every entry in the sidebar and an empty page for unbuilt features" do
    sign_in
    Admin::Menu::PLACEHOLDERS.each_key do |key|
      get public_send("admin_#{key}_path")
      expect(response).to have_http_status(:ok), "#{key} should render"
    end
    get "/admin"
    Admin::Menu::GROUPS.flat_map(&:last).each do |entry|
      expect(response.body).to include(CGI.escapeHTML(I18n.t("admin_menu.items.#{entry.key}", locale: :fr)))
    end
  end

  it "keeps platform-only sessions out of store placeholder pages" do
    platform_user = User.create!(email: "platform-#{SecureRandom.hex(5)}@example.test", password: password, admin: true, super_admin: true)
    sign_in(platform_user, workspace: nil)
    get "/admin/analytics"
    expect(response).to redirect_to(admin_platform_path)
  end
end
