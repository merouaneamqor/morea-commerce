require "rails_helper"

RSpec.describe "Platform feature flags", type: :request do
  let(:password) { "synthetic-feature-flag-password-123" }
  let!(:super_admin) do
    User.create!(
      email: "feature-flags-platform-#{SecureRandom.hex(5)}@example.test",
      password: password,
      admin: true,
      super_admin: true
    )
  end
  let!(:store) do
    Store.create!(
      slug: "feature-flags-#{SecureRandom.hex(5)}",
      name: "Feature flag workspace",
      currency: "MAD",
      storefront_enabled: true
    )
  end
  let!(:other_store) do
    Store.create!(
      slug: "other-feature-flags-#{SecureRandom.hex(5)}",
      name: "Other feature flag workspace",
      currency: "MAD",
      storefront_enabled: true
    )
  end
  let!(:merchant) do
    store.users.create!(
      email: "feature-flags-merchant-#{SecureRandom.hex(5)}@example.test",
      password: password,
      admin: true
    )
  end

  def sign_in(user, host: Store.base_domain)
    host! host
    post "/admin/login", params: { email: user.email, password: password }
    expect(response).to have_http_status(:redirect)
  end

  it "allows a super admin to view the feature flags page" do
    sign_in(super_admin)

    get "/admin/feature_flags"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(store.name, other_store.name)
  end

  it "denies feature flag management to a merchant administrator" do
    sign_in(merchant, host: "#{store.slug}.#{Store.base_domain}")

    get "/admin/feature_flags"

    expect(response).to redirect_to(admin_root_path)
  end

  it "enables and disables the theme editor for only the selected workspace" do
    sign_in(super_admin)

    patch "/admin/feature_flags/#{store.id}", params: {
      feature_flag: { storefront_theme_editor_enabled: "1" }
    }

    expect(response).to redirect_to(admin_feature_flags_path)
    expect(store.reload).to be_storefront_theme_editor_enabled
    expect(other_store.reload).not_to be_storefront_theme_editor_enabled

    patch "/admin/feature_flags/#{store.id}", params: {
      feature_flag: { storefront_theme_editor_enabled: "0" }
    }

    expect(response).to redirect_to(admin_feature_flags_path)
    expect(store.reload).not_to be_storefront_theme_editor_enabled
    expect(other_store.reload).not_to be_storefront_theme_editor_enabled
  end

  it "gates the merchant themes index until the workspace flag is enabled" do
    sign_in(merchant, host: "#{store.slug}.#{Store.base_domain}")

    get "/admin/themes"

    expect(response).to redirect_to(admin_online_store_path)
    expect(flash[:alert]).to eq("The theme editor is not enabled for this workspace.")

    store.update!(storefront_theme_editor_enabled: true)
    get "/admin/themes"

    expect(response).to have_http_status(:ok)
  end
end
