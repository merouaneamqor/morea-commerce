require "rails_helper"

# The public demo: entry, realistic fictitious data, every menu page opens, and nothing can be changed.
RSpec.describe "Seller demo", type: :request do
  let(:apex) { { "HOST" => Store.base_domain } }

  before { host! Store.base_domain }

  def enter_demo(**params)
    get "/demo", params: params
    expect(response).to have_http_status(:redirect)
  end

  # Opens a page like a browser does: follows the redirects (the seller addresses redirect to the admin ones) but fails if the visitor is sent to sign in.
  def open_page(path)
    get path
    3.times do
      break unless response.redirect?
      expect(response.location).not_to include("/login"), "#{path} sent the visitor to sign in"
      follow_redirect!
    end
  end

  it "signs the visitor in to the fictitious workspace and shows the demo bar" do
    enter_demo
    follow_redirect!
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("demo-banner")
    store = Demo::Workspace.store
    expect(store.orders.count).to be >= Demo::Workspace::ORDER_COUNT
    expect(store.products.count).to eq(8)
    expect(store.users.where(confirmation_role: "agent").count).to eq(3)
    expect(store.storefront_enabled).to be(false)
  end

  it "opens every page of the seller menu" do
    enter_demo
    %w[/dashboard /commandes /confirmation /clients /livraison /produits /comptabilite /equipe /integrations].each do |path|
      open_page(path)
      expect(response).to have_http_status(:ok), "#{path} answered #{response.status}"
      expect(response.body).to include("demo-banner")
    end
  end

  it "opens the other pages a visitor can click on" do
    enter_demo
    store = Demo::Workspace.store
    order = store.orders.order(:created_at).last
    product = store.products.first
    [ "/admin/orders/#{order.id}", "/admin/products/#{product.to_param}/edit", "/admin/whatsapp", "/admin/discounts", "/admin/collections", "/admin/staff", "/admin/media",
      "/admin/confirmations/dashboard", "/admin/confirmations/analytics", "/admin/confirmations/assignments", "/admin/confirmations/rules", "/admin/confirmations/attendance" ].each do |path|
      open_page(path)
      expect(response).to have_http_status(:ok), "#{path} answered #{response.status}"
    end
  end

  it "shows the agent's desk with ?role=agent" do
    enter_demo(role: "agent")
    follow_redirect!
    expect(response).to have_http_status(:ok)
  end

  it "refuses every change in the demo workspace" do
    enter_demo
    store = Demo::Workspace.store
    before_count = store.products.count
    post "/admin/products", params: { product: { name: "Pirate", price: "10" } }
    expect(response).to redirect_to(admin_root_path).or have_http_status(:forbidden)
    expect(store.products.reload.count).to eq(before_count)
    patch "/admin/store", params: { store: { name: "Hacked" } }
    expect(store.reload.name).to eq("Atlas Beauté")
    delete "/admin/products/#{store.products.first.id}"
    expect(store.products.reload.count).to eq(before_count)
  end

  it "keeps the demo apart from other workspaces" do
    other = Store.create!(slug: "other-#{SecureRandom.hex(4)}", name: "Autre", currency: "MAD")
    other_customer = other.customers.create!(name: "Secret Client", phone: "0699999999")
    other.orders.create!(customer: other_customer, number: "SECRET1", currency: "MAD", customer_name: "Secret Client", customer_phone: "0699999999", customer_city: "Fès", customer_address: "x",
                         subtotal_cents: 100, total_cents: 100)
    enter_demo
    open_page("/commandes")
    expect(response.body).not_to include("Secret Client")
    open_page("/clients")
    expect(response.body).not_to include("Secret Client")
  end

  it "is only served on the platform host" do
    host! "boutique.example.test"
    get "/demo"
    expect(response).to have_http_status(:not_found)
  end
end
