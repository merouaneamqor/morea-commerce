require "rails_helper"

RSpec.describe "Platform home page gates", type: :request do
  let(:password) { "synthetic-home-gate-password-123" }
  let!(:super_admin) do
    User.create!(
      email: "home-gate-platform-#{SecureRandom.hex(5)}@example.test",
      password: password,
      admin: true,
      super_admin: true
    )
  end
  let!(:store) do
    Store.create!(
      slug: "home-gate-#{SecureRandom.hex(5)}",
      name: "Home gate workspace",
      currency: "MAD",
      storefront_enabled: true
    )
  end

  before { host! Store.base_domain }

  def sign_in(user, host: Store.base_domain)
    host! host
    post "/admin/login", params: { email: user.email, password: password }
    expect(response).to have_http_status(:redirect)
    host! Store.base_domain
  end

  it "shows the live home page while both flags are off" do
    get "/"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("platform-hero")
    expect(response.body).not_to include("data-home-gate")
  end

  it "shows under maintenance, including in Arabic, and keeps admin sign-in available" do
    PlatformSetting.current.update!(home_maintenance: true, home_coming_soon: true)

    get "/", params: { locale: "ar" }

    expect(response).to have_http_status(:service_unavailable)
    expect(response.headers["Retry-After"]).to eq("3600")
    expect(response.headers["Cache-Control"]).to eq("private, no-store")
    expect(response.body).to include('data-home-gate="maintenance"')
    expect(response.body).to include('dir="rtl"')
    expect(response.body).to include(I18n.t("platform_home.gate.maintenance.heading", locale: :ar))
    expect(response.body).to include('name="robots" content="noindex, nofollow"')

    get "/admin/login"
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("data-home-gate")
  end

  it "shows coming soon in English when that flag is the only one on" do
    PlatformSetting.current.update!(home_coming_soon: true)

    get "/", params: { locale: "en" }

    expect(response).to have_http_status(:ok)
    expect(response.headers["Cache-Control"]).to eq("private, no-store")
    expect(response.body).to include('data-home-gate="coming_soon"')
    expect(response.body).to include(I18n.t("platform_home.gate.coming_soon.heading", locale: :en))
    expect(response.body).not_to include("platform-hero")
  end

  it "leaves a storefront on its own host unchanged" do
    PlatformSetting.current.update!(home_maintenance: true, home_coming_soon: true)

    host! "#{store.slug}.#{Store.base_domain}"
    get "/fr"

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("data-home-gate")
  end

  it "lets a super admin enable and disable each home page flag" do
    sign_in(super_admin)

    get "/superadmin/feature_flags"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Public home page", "Under maintenance", "Coming soon")

    patch "/superadmin/feature_flags/update_home", params: { flag: "home_coming_soon", enabled: "1" }
    expect(response).to redirect_to(superadmin_feature_flags_path)
    expect(PlatformSetting.current.reload).to be_home_coming_soon
    expect(PlatformSetting.current).not_to be_home_maintenance

    patch "/superadmin/feature_flags/update_home", params: { flag: "home_maintenance", enabled: "1" }
    expect(PlatformSetting.current.reload.home_page).to eq("maintenance")

    patch "/superadmin/feature_flags/update_home", params: { flag: "home_maintenance", enabled: "0" }
    expect(PlatformSetting.current.reload.home_page).to eq("coming_soon")

    patch "/superadmin/feature_flags/update_home", params: { flag: "storefront_theme_editor_enabled", enabled: "1" }
    expect(response).to redirect_to(superadmin_feature_flags_path)
    expect(flash[:alert]).to eq("Unknown home page flag.")
    expect(PlatformSetting.current.reload.home_page).to eq("coming_soon")
  end

  it "does not let a merchant change the home page flags" do
    merchant = store.users.create!(
      email: "home-gate-merchant-#{SecureRandom.hex(5)}@example.test",
      password: password,
      admin: true
    )
    sign_in(merchant, host: "#{store.slug}.#{Store.base_domain}")

    patch "/superadmin/feature_flags/update_home", params: { flag: "home_maintenance", enabled: "1" }

    expect(response).to redirect_to(admin_root_path)
    expect(PlatformSetting.current).not_to be_home_maintenance
  end
end
