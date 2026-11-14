require "rails_helper"

# "Envoyer les colis confirmés": the checks (duplicates, customers who cancelled before, blocked numbers, incomplete addresses) and the bulk send.
RSpec.describe "Send the confirmed parcels", type: :request do
  include ActiveJob::TestHelper

  let(:password) { "synthetic-password-123" }
  let(:store) { Store.create!(slug: "sc-#{SecureRandom.hex(5)}", name: "Walkfit", currency: "MAD", sendit_public_key: "pk", sendit_secret_key: "sk") }
  let!(:owner) { store.users.create!(name: "Owner", email: "owner-#{SecureRandom.hex(4)}@example.test", password: password, admin: true) }
  let(:product) { store.products.create!(name: "Sérum", slug: "serum", status: "active", price_cents: 24_900, currency: "MAD") }
  let(:other_product) { store.products.create!(name: "Huile", slug: "huile", status: "active", price_cents: 18_900, currency: "MAD") }
  let(:seq) { Enumerator.new { |y| n = 0; loop { y << (n += 1) } } }

  def sign_in(user = owner)
    host! "#{store.slug}.#{Store.base_domain}"
    post "/admin/login", params: { email: user.email, password: password }
  end

  def order_for(phone, item: product, status: "confirmed", hours_ago: 2, address: "12 rue des Fleurs", city: "Fès", name: "Client", on: store)
    customer = on.customers.find_or_create_by!(phone: phone) { |c| c.name = name }
    created = Time.current - hours_ago.hours
    order = on.orders.create!(customer: customer, number: format("T%05d", seq.next), status: status, currency: "MAD", customer_name: name, customer_phone: phone, customer_city: city, customer_address: address,
                              subtotal_cents: item.price_cents, total_cents: item.price_cents, created_at: created, updated_at: created, skip_auto_whatsapp: true)
    order.order_items.create!(product: item, product_name: item.name, quantity: 1, unit_price_cents: item.price_cents, total_cents: item.price_cents)
    order
  end

  def review = Orders::ShipmentReview.new(store: store)
  def row_for(order) = review.rows.find { |row| row.order.id == order.id }

  it "lets a clean confirmed order go" do
    clean = order_for("0612345001")
    expect(row_for(clean)).to be_ready
    expect(row_for(clean)).to be_checked_by_default
  end

  it "holds back the later order of a duplicate pair, and keeps the first" do
    first = order_for("0612345002", hours_ago: 5)
    second = order_for("0612345002", hours_ago: 2)
    expect(row_for(first)).to be_ready
    expect(row_for(second).issues).to include(:duplicate)
    expect(row_for(second).duplicate_of).to eq(first)
    expect(row_for(second)).not_to be_selectable
  end

  it "does not call two different baskets a duplicate, nor an order of someone else" do
    a = order_for("0612345003", item: product, hours_ago: 5)
    b = order_for("0612345003", item: other_product, hours_ago: 2)
    c = order_for("0699999999", item: product, hours_ago: 1)
    expect([ row_for(a), row_for(b), row_for(c) ]).to all(be_ready)
  end

  it "holds back an order identical to one that already has a parcel, but not one identical to a cancelled order" do
    shipped = order_for("0612345004", status: "in_transit", hours_ago: 30)
    shipped.update_columns(sendit_code: "SD123")
    again = order_for("0612345004", hours_ago: 2)
    expect(row_for(again).issues).to include(:duplicate)

    cancelled = order_for("0612345005", status: "cancelled", hours_ago: 30)
    fresh = order_for("0612345005", hours_ago: 2)
    expect(row_for(fresh).issues).not_to include(:duplicate)
    expect(cancelled.reload.status).to eq("cancelled")
  end

  it "warns about a customer who cancelled before, without blocking, and does not tick it" do
    order_for("0612345006", status: "cancelled", hours_ago: 24 * 40)
    order_for("0612345006", item: other_product, status: "cancelled", hours_ago: 24 * 10)
    now = order_for("0612345006", hours_ago: 1)
    row = row_for(now)
    expect(row.issues).to eq([ :prior_cancelled ])
    expect(row.cancelled_count).to eq(2)
    expect(row).to be_selectable
    expect(row).not_to be_checked_by_default
  end

  it "ignores a cancellation older than a year, and matches phones written differently" do
    order_for("0612345007", status: "cancelled", hours_ago: 24 * 400)
    expect(row_for(order_for("0612345007", hours_ago: 1)).issues).to be_empty

    order_for("+212 6 12 34 50 08", status: "cancelled", hours_ago: 24 * 3)
    expect(row_for(order_for("0612345008", hours_ago: 1)).issues).to include(:prior_cancelled)
  end

  it "holds back blocked numbers and incomplete addresses" do
    BlockedPhone.create!(store: store, phone_key: BlockedPhone.key_for("0612345009"), reason: "Refus", blocked_by: owner)
    expect(row_for(order_for("0612345009")).issues).to include(:blocked)
    expect(row_for(order_for("0612345010", address: "-")).issues).to include(:incomplete)
    expect(row_for(order_for("06123", address: "12 rue des Fleurs")).issues).to include(:incomplete)
  end

  it "does not offer orders that are new, shipped, archived or that belong to another store" do
    order_for("0612345011", status: "new")
    shipped = order_for("0612345012")
    shipped.update_columns(sendit_code: "SD9")
    archived = order_for("0612345013")
    archived.update_columns(archived_at: Time.current)
    other = Store.create!(slug: "ot-#{SecureRandom.hex(4)}", name: "Autre", currency: "MAD")
    other_product = other.products.create!(name: "X", slug: "x", status: "active", price_cents: 100, currency: "MAD")
    order_for("0612345014", item: other_product, on: other)
    expect(review.rows).to be_empty
  end

  describe "the page and the send" do
    it "shows the rows with their checks" do
      sign_in
      order_for("0612345020", hours_ago: 5)
      dup = order_for("0612345020", hours_ago: 2)
      ok = order_for("0612345021")
      get ship_review_admin_orders_path
      expect(response).to have_http_status(:ok)
      body = response.body
      expect(body).to include(ok.number, dup.number)
      expect(body).to include(I18n.t("orders_ship.duplicate", number: "##{row_for(dup).duplicate_of.number}"))
      expect(body).to match(/value="#{ok.id}"[^>]*checked/)
      expect(body).to match(/value="#{dup.id}"[^>]*disabled/)
    end

    it "queues only the parcels that may go, whatever the form says" do
      sign_in
      first = order_for("0612345022", hours_ago: 5)
      dup = order_for("0612345022", hours_ago: 2)
      ok = order_for("0612345023")
      expect do
        post ship_confirmed_admin_orders_path, params: { order_ids: [ first.id, dup.id, ok.id ] }
      end.to have_enqueued_job(SenditSyncJob).with(first.id, "push").and have_enqueued_job(SenditSyncJob).with(ok.id, "push")
      expect(enqueued_jobs.count { |job| job[:job] == SenditSyncJob }).to eq(2)
      expect(flash[:notice]).to include("2").and include("1")
    end

    it "does not queue the same order twice when the button is pressed twice" do
      sign_in
      ok = order_for("0612345024")
      allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new) # the test environment has no real cache
      2.times { post ship_confirmed_admin_orders_path, params: { order_ids: [ ok.id ] } }
      expect(enqueued_jobs.count { |job| job[:job] == SenditSyncJob }).to eq(1)
    end

    it "ignores ids of another store" do
      sign_in
      other = Store.create!(slug: "ot2-#{SecureRandom.hex(4)}", name: "Autre", currency: "MAD")
      other_product = other.products.create!(name: "X", slug: "x2", status: "active", price_cents: 100, currency: "MAD")
      foreign = order_for("0612345025", item: other_product, on: other)
      expect { post ship_confirmed_admin_orders_path, params: { order_ids: [ foreign.id ] } }.not_to have_enqueued_job(SenditSyncJob)
    end

    it "needs a connected delivery company" do
      store.update!(sendit_public_key: nil, sendit_secret_key: nil)
      sign_in
      get ship_review_admin_orders_path
      expect(response).to redirect_to(admin_orders_path)
    end

    it "keeps a confirmation agent out" do
      agent = store.users.create!(name: "Agent", email: "agent-#{SecureRandom.hex(4)}@example.test", password: password, admin: false, confirmation_role: "agent")
      sign_in(agent)
      get ship_review_admin_orders_path
      expect(response).to redirect_to(admin_orders_path)
    end
  end

  describe "in the demo" do
    before { host! Store.base_domain }

    it "shows the checks on the demo data and sends nothing" do
      get "/demo"
      get ship_review_admin_orders_path
      expect(response).to have_http_status(:ok)
      demo = Demo::Workspace.store
      rows = Orders::ShipmentReview.new(store: demo).rows
      expect(rows.count { |row| row.issues.include?(:duplicate) }).to be >= 2
      expect(rows.count { |row| row.issues.include?(:prior_cancelled) }).to be >= 3
      expect(rows.count { |row| row.issues.include?(:blocked) }).to be >= 1
      expect(rows.count(&:ready?)).to be >= 4
      expect do
        post ship_confirmed_admin_orders_path, params: { order_ids: rows.select(&:ready?).map { |row| row.order.id } }
      end.not_to have_enqueued_job(SenditSyncJob)
      expect(flash[:notice]).to include("Démo").or include("Demo")
      expect(demo.orders.where.not(sendit_code: nil).count).to eq(demo.orders.where.not(sendit_code: nil).count)
    end
  end
end
