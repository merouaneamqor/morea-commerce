require "rails_helper"
require "nokogiri"

RSpec.describe "Admin online store builder", type: :request do
  let(:password) { "synthetic-password-123" }
  let(:store) do
    Store.create!(slug: "builder-#{SecureRandom.hex(5)}", name: "Synthetic builder workspace",
      currency: "MAD", storefront_enabled: true)
  end
  let(:staff) do
    store.users.create!(email: "builder-#{SecureRandom.hex(5)}@example.test", password: password, admin: true)
  end

  def workspace(**attributes)
    Store.create!({ slug: "builder-#{SecureRandom.hex(5)}", name: "Foreign builder workspace",
      currency: "MAD", storefront_enabled: true }.merge(attributes))
  end

  def sign_in(user = staff, workspace: store)
    host! workspace ? "#{workspace.slug}.#{Store.base_domain}" : Store.base_domain
    post "/admin/login", params: { email: user.email, password: password }
    expect(response).to have_http_status(:redirect)
  end

  def document
    Nokogiri::HTML(response.body)
  end

  def resource_count(resource)
    document.at_css(%([data-online-store-count="#{resource}"]))&.text&.to_i
  end

  it "requires authentication" do
    host! "#{store.slug}.#{Store.base_domain}"

    get "/admin/online_store"

    expect(response).to redirect_to(admin_login_path)
  end

  it "renders the tenant-scoped builder hub and its management destinations" do
    2.times do |index|
      store.products.create!(name: "Own product #{index}", slug: "own-product-#{index}", status: "active",
        price_cents: 10_000 + index, stock: 1)
    end
    store.collections.create!(name: "Own collection", slug: "own-collection")
    store.pages.create!(slug: "own-page", published: true, template: "content")
    store.home_sections.create!(kind: "image_with_text", position: 1, visible: true)
    store.menu_items.create!(menu: "header", link: "home", position: 1)

    foreign = workspace
    5.times do |index|
      foreign.products.create!(name: "Foreign product #{index}", slug: "foreign-product-#{index}", status: "active",
        price_cents: 20_000 + index, stock: 1)
    end
    3.times { |index| foreign.collections.create!(name: "Foreign collection #{index}", slug: "foreign-collection-#{index}") }
    foreign.pages.create!(slug: "foreign-page", published: true, template: "content")
    foreign.home_sections.create!(kind: "image_with_text", position: 1, visible: true)
    foreign.menu_items.create!(menu: "header", link: "home", position: 1)

    sign_in
    get "/admin/online_store", params: { locale: "en" }

    expect(response).to have_http_status(:ok)
    hrefs = document.css("a[href]").map { |link| link["href"] }
    expect(hrefs).to include(admin_products_path, admin_home_sections_path, admin_pages_path,
      admin_menu_items_path, edit_admin_store_path)
    expect(resource_count("products")).to eq(2)
    expect(resource_count("collections")).to eq(1)
    expect(resource_count("pages")).to eq(1)
    expect(resource_count("sections")).to eq(1)
    expect(resource_count("navigation")).to eq(1)
    expect(document.at_css("[data-online-store-readiness]")).to be_present
  end

  it "offers external FR, EN and AR previews for a published storefront" do
    sign_in

    get "/admin/online_store", params: { locale: "en" }

    preview_links = document.css('a[data-storefront-preview][target="_blank"]')
    expect(preview_links.map { |link| link["href"] }).to contain_exactly(
      "#{store.origin}/fr", "#{store.origin}/en", "#{store.origin}/ar"
    )
  end

  it "keeps an unpublished storefront editable without exposing public preview links" do
    store.update!(storefront_enabled: false)
    sign_in

    get "/admin/online_store", params: { locale: "en" }

    expect(response).to have_http_status(:ok)
    expect(document.css("a[data-storefront-preview]")).to be_empty
    publish_link = document.at_css(%(a[href="#{edit_admin_store_path(anchor: "storefront")}"]))
    expect(publish_link).to be_present

    get "/en"
    expect(response).to have_http_status(:not_found)
  end

  it "redirects a platform-only administrator without a selected workspace" do
    platform_user = User.create!(email: "platform-builder-#{SecureRandom.hex(5)}@example.test", password: password,
      admin: true, super_admin: true)
    sign_in(platform_user, workspace: nil)

    get "/admin/online_store"

    expect(response).to redirect_to(admin_platform_path)
  end
end
