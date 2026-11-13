require "rails_helper"
require "nokogiri"

# What a confirmation agent sees: their own dashboard, their own call center queue (as the owner's attribution rules decide) and their own billing.
RSpec.describe "Agent workspace", type: :request do
  let(:password) { "synthetic-password-123" }
  let(:store) { Store.create!(slug: "ag-#{SecureRandom.hex(5)}", name: "Walkfit", currency: "MAD") }
  let!(:saida) { store.users.create!(name: "Saida", email: "saida-#{SecureRandom.hex(4)}@example.test", password: password, admin: false, confirmation_role: "agent", pay_per_delivery_cents: 800) }
  let!(:omar) { store.users.create!(name: "Omar", email: "omar-#{SecureRandom.hex(4)}@example.test", password: password, admin: false, confirmation_role: "agent", pay_per_delivery_cents: 800) }
  let(:customer) { store.customers.create!(name: "Client", phone: "0612345678") }

  def sign_in(user)
    host! "#{store.slug}.#{Store.base_domain}"
    post "/admin/login", params: { email: user.email, password: password }
  end

  def page = Nokogiri::HTML(response.body)
  def host = "#{store.slug}.#{Store.base_domain}"

  def make(number, attributed: nil)
    order = store.orders.create!(customer: customer, number: number, status: "new", currency: "MAD", customer_name: "Client #{number}", customer_phone: "0612345678",
      customer_city: "Fès", customer_address: "Rue 1", subtotal_cents: 20_000, total_cents: 20_000)
    OrderConfirmation.create!(store: store, order: order, disposition: "pending", attributed_user: attributed) if attributed
    order
  end

  def queue_numbers = page.css("[data-order-row], [data-order-number]").map { |node| node["data-order-row"] || node["data-order-number"] }

  it "gives the agent a menu with only their dashboard, their call center and their billing" do
    sign_in(saida)
    get admin_my_stats_path

    expect(response).to have_http_status(:ok)
    labels = page.css("[data-sidebar-nav] > ul > li").map { |item| item.text.squish }
    expect(labels.join(" ")).to include("Tableau de bord", "Centre d'appels", "Facturation")
    expect(page.at_css("[data-sidebar-nav]").text).not_to include("Comptabilité", "Équipe", "Produits", "Commandes", "Clients", "Livraison")
  end

  it "shows an agent only their own payments and deductions in Facturation" do
    AgentPayment.create!(store: store, user: saida, amount_cents: 1600, paid_at: 2.days.ago)
    AgentPayment.create!(store: store, user: omar, amount_cents: 99_900, paid_at: 1.day.ago)
    sign_in(saida)
    get admin_my_billing_path

    expect(response).to have_http_status(:ok)
    expect(page.css("[data-payment]").size).to eq(1)
    expect(response.body).to include("16 MAD")
    expect(response.body).not_to include("999 MAD")
    expect(response.body).not_to include(omar.name)
  end

  it "keeps the other pages of the store closed to an agent" do
    sign_in(saida)
    get admin_users_path
    expect(response).to redirect_to(admin_my_stats_path)
    get admin_accounting_path
    expect(response).to redirect_to(admin_my_stats_path)
  end

  it "follows the owner's attribution rules: with an active rule an agent sees only the orders given to them" do
    mine = make("MINE", attributed: saida)
    make("THEIRS", attributed: omar)
    open_pool = make("OPEN")
    sign_in(saida)

    get "/admin/confirmations", params: { filter: "available" }
    expect(response.body).to include("OPEN") # no rule yet: the open pool is shared

    rule = store.assignment_rules.new(name: "Règle", distribution: "equal")
    [ saida, omar ].each { |agent| rule.assignment_rule_agents.build(user: agent) }
    rule.save!

    get "/admin/confirmations", params: { filter: "available" }
    expect(response.body).to include("MINE")
    expect(response.body).not_to include("THEIRS")
    expect(response.body).not_to include("OPEN")
    get admin_order_path(open_pool)
    expect(response).to have_http_status(:not_found)
    get admin_order_path(mine)
    expect(response).to have_http_status(:ok)
  end
  it "clocks in and out in place, and counts the time in the agent's own statistics" do
    sign_in(saida)
    get "/admin/confirmations/center"
    expect(response).to have_http_status(:ok)

    post clock_in_admin_confirmations_path, headers: { "HTTP_REFERER" => "http://#{host}/admin/confirmations/center" }
    expect(response).to redirect_to("http://#{host}/admin/confirmations/center")
    expect(ConfirmationShift.open.where(user: saida)).to exist
    follow_redirect!
    expect(page.at_css("[data-shift-running]")).to be_present

    ConfirmationShift.open.find_by(user: saida).update_columns(started_at: 90.minutes.ago)
    get admin_my_stats_path
    expect(page.at_css("[data-my-hours] [data-worked]")["data-worked"].to_i).to be_between(5390, 5500)
    expect(page.at_css("[data-my-hours]").text).to include("1:3")

    post clock_out_admin_confirmations_path, headers: { "HTTP_REFERER" => "http://#{host}/admin/my_stats" }
    expect(response).to redirect_to("http://#{host}/admin/my_stats")
    expect(ConfirmationShift.open.where(user: saida)).not_to exist
  end

  it "shows the owner each agent's time worked next to the comparison" do
    owner = store.users.create!(name: "Owner", email: "owner-#{SecureRandom.hex(4)}@example.test", password: password, admin: true)
    ConfirmationShift.create!(store: store, user: saida, started_at: 2.hours.ago, ended_at: 30.minutes.ago)
    sign_in(owner)
    get "/admin/confirmations/analytics", params: { view: "agents" }

    expect(response).to have_http_status(:ok)
    expect(page.at_css("[data-hours-head]")).to be_present
    expect(page.at_css("[data-agent-row='#{saida.id}'] [data-worked]")["data-worked"].to_i).to be_between(5390, 5410)
    expect(page.at_css("[data-agent-row='#{omar.id}'] [data-worked]")["data-worked"]).to eq("0")
  end

  it "lists the agent's orders with their status on the dashboard, searchable, in every language, and never a colleague's" do
    mine = make("MINE-1", attributed: saida)
    make("MINE-2", attributed: saida)
    make("THEIRS-1", attributed: omar)
    mine.update!(customer_name: "Hamza Alaoui")
    sign_in(saida)

    get admin_my_stats_path
    expect(page.css("[data-my-orders] [data-order-row]").map { |row| row["data-order-row"] }).to contain_exactly("MINE-1", "MINE-2")
    expect(page.at_css("[data-order-row='MINE-1'] [data-status]")["data-status"]).to eq("new")

    get admin_my_stats_path, params: { q: "alaoui" }
    expect(page.css("[data-my-orders] [data-order-row]").map { |row| row["data-order-row"] }).to eq([ "MINE-1" ])
    expect(page.at_css("[data-clear-search]")).to be_present
    get admin_my_stats_path, params: { q: "THEIRS" }
    expect(page.at_css("[data-no-orders]")).to be_present

    SellerHelper.untranslated.clear
    %w[en es ar].each { |locale| get admin_my_stats_path, params: { locale: locale } }
    expect(SellerHelper.untranslated.to_a).to eq([])
  end

  it "lets an agent create an order by hand, like the owner, and the order is theirs" do
    product = store.products.create!(name: "Survêtement", sku: "SURV-01", price_cents: 25_000, status: "active", track_inventory: true, stock: 10)
    store.assignment_rules.new(name: "Règle", distribution: "equal").tap { |rule| [ saida, omar ].each { |agent| rule.assignment_rule_agents.build(user: agent) } }.save!
    sign_in(saida)

    get "/admin/confirmations/center"
    expect(page.at_css("a[href='#{new_admin_order_path}']")).to be_present
    get admin_my_stats_path
    expect(page.at_css("a[href='#{new_admin_order_path}']")).to be_present

    get new_admin_order_path
    expect(response).to have_http_status(:ok)
    expect(page.at_css("select[name='order[agent_id]']")).to be_nil
    get "/admin/orders/product_search", params: { q: "Survêt" }
    expect(response).to have_http_status(:ok)

    expect {
      post "/admin/orders", params: { order: { name: "Karim", phone: "0612345678", city: "Casablanca", address: "Rue 1", agent_id: omar.id, lines: [ { product_id: product.id, quantity: 1 } ] } }
    }.to change(store.orders, :count).by(1)
    order = store.orders.order(:id).last
    expect(order.order_confirmation).to have_attributes(attributed_user_id: saida.id, assigned_user_id: nil)
    expect(response).to redirect_to(admin_order_path(order))

    get admin_my_stats_path
    expect(page.css("[data-my-orders] [data-order-row]").map { |row| row["data-order-row"] }).to include(order.number)
    get admin_order_path(order)
    expect(response).to have_http_status(:ok)
    patch admin_order_path(order), params: { order: { notes: "x" } }
    expect(response).to redirect_to(admin_orders_path) # an existing order still cannot be changed by an agent
  end

  describe "the store's logo instead of the platform name" do
    let(:png) { Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==") }

    def upload(name, content, type)
      file = Tempfile.new([ "logo", File.extname(name) ])
      file.binmode
      file.write(content)
      file.rewind
      Rack::Test::UploadedFile.new(file.path, type, true, original_filename: name)
    end

    it "shows the agent the store name when there is no logo, and the logo once the owner uploaded one, never seallo" do
      sign_in(saida)
      get admin_my_stats_path
      brand = page.at_css("[data-agent-brand]")
      expect(brand.text.squish).to eq("Walkfit")
      expect(page.at_css("[data-sidebar-nav]").text).not_to include("seallo")

      owner = store.users.create!(name: "Owner", email: "own-#{SecureRandom.hex(4)}@example.test", password: password, admin: true)
      delete admin_logout_path rescue nil
      sign_in(owner)
      patch admin_store_path, params: { store: { logo: upload("logo.png", png, "image/png") } }
      expect(response).to redirect_to(edit_admin_store_path)
      expect(store.reload.logo).to be_attached
      get edit_admin_store_path
      expect(page.at_css("[data-store-logo-preview] img")).to be_present
      get admin_orders_path
      expect(page.at_css("[data-sidebar-nav]").text).to include("seallo")  # the owner keeps the platform brand

      delete admin_logout_path rescue nil
      sign_in(saida)
      get admin_my_stats_path
      expect(page.at_css("[data-agent-brand] img")["alt"]).to eq("Walkfit")
      expect(page.at_css("[data-sidebar-nav]").text).not_to include("seallo")
    end

    it "refuses a logo that is not an image, and lets the owner remove it" do
      owner = store.users.create!(name: "Owner", email: "own-#{SecureRandom.hex(4)}@example.test", password: password, admin: true)
      sign_in(owner)
      patch admin_store_path, params: { store: { logo: upload("logo.txt", "not an image", "text/plain") } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(store.reload.logo).not_to be_attached

      patch admin_store_path, params: { store: { logo: upload("logo.png", png, "image/png") } }
      expect(store.reload.logo).to be_attached
      expect { patch admin_store_path, params: { store: { remove_logo: "1" } } }.to have_enqueued_job(ActiveStorage::PurgeJob)
    end
  end
end
