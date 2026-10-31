# frozen_string_literal: true

require "rails_helper"
require "timeout"

RSpec.describe Connections::SealloConnect do
  let(:store) { Store.create!(slug: "seallo-connect-#{SecureRandom.hex(5)}", name: "Synthetic workspace", currency: "MAD", storefront_enabled: false) }
  let(:other_store) { Store.create!(slug: "seallo-other-#{SecureRandom.hex(5)}", name: "Other synthetic workspace", currency: "MAD", storefront_enabled: false) }
  let(:staff) { store.users.create!(email: "seallo-#{SecureRandom.hex(5)}@example.test", password: "synthetic-password-123", admin: true) }
  let(:shop) { "synthetic-#{SecureRandom.hex(5)}.myshopify.com" }
  let(:code) { SealloConnectionCode.issue!(store: store, user: staff) }
  let(:verification) do
    { "shop" => { "myshopifyDomain" => shop }, "currentAppInstallation" => { "accessScopes" => [ { "handle" => "read_orders" } ] } }
  end

  before do
    allow(Connections::SealloBridge).to receive(:graphql).and_return(verification)
    allow(Connections::SealloBridge).to receive(:entitlement).and_return(
      "active" => true, "current_period_start" => 1.day.ago.iso8601, "current_period_end" => 29.days.from_now.iso8601,
      "plan_name" => "Seallo Basic", "order_limit" => 19
    )
  end

  def connect
    described_class.call(code: code, shop: shop)
  end

  it "links one shop to the issuing workspace, consumes the code and stores no Shopify credentials" do
    result = connect
    expect(result.store).to eq(store)
    expect(result.shopify_app).to eq("seallo_connect")
    expect(result).to be_shopify_api_connected
    expect(result.shopify_access_token_ciphertext).to be_nil
    expect(result.shopify_refresh_token_ciphertext).to be_nil
    expect(result.shopify_granted_scopes).to eq([ "read_orders" ])
    expect(SealloConnectionCode.find_by!(digest: Digest::SHA256.hexdigest(code)).consumed_at).to be_present
    expect(ShopifyOrdersSyncJob).to have_been_enqueued.with(result.id)
    expect(Connections::SealloBridge).to have_received(:graphql).with(shop: shop, query: Connections::ShopifyApi::VERIFY_QUERY, variables: {})
  end

  it "rejects replay without queuing another import" do
    connect
    clear_enqueued_jobs
    expect { connect }.to raise_error(described_class::Error, "invalid_code")
    expect(ShopifyOrdersSyncJob).not_to have_been_enqueued
    expect(store.store_connections.count).to eq(1)
  end

  it "invalidates a previous code when staff requests a replacement" do
    old_code = code
    replacement = SealloConnectionCode.issue!(store: store, user: staff)
    expect(replacement).not_to eq(old_code)
    expect { described_class.call(code: old_code, shop: shop) }.to raise_error(described_class::Error, "invalid_code")
  end

  it "rejects expired codes and leaves them unconsumed" do
    pending = SealloConnectionCode.find_by!(digest: Digest::SHA256.hexdigest(code))
    pending.update!(expires_at: 1.second.ago)
    expect { connect }.to raise_error(described_class::Error, "invalid_code")
    expect(pending.reload.consumed_at).to be_nil
    expect(store.store_connections).to be_empty
  end

  it "rechecks staff status, role and workspace at redemption" do
    [ { status: "suspended" }, { admin: false }, { store_id: other_store.id } ].each do |attributes|
      fresh_code = SealloConnectionCode.issue!(store: store, user: staff)
      original = staff.attributes.slice(*attributes.keys.map(&:to_s))
      staff.update_columns(attributes)
      expect { described_class.call(code: fresh_code, shop: shop) }.to raise_error(described_class::Error, "invalid_code")
      staff.update_columns(original)
      staff.reload
    end
  end

  it "requires an active Shopify subscription at redemption" do
    code
    allow(Connections::SealloBridge).to receive(:entitlement).and_return("active" => false)
    expect { connect }.to raise_error(described_class::Error, "subscription_required")
    expect(store.store_connections).to be_empty
  end

  it "rolls back the connection and preserves the code when identity verification fails" do
    verification["shop"]["myshopifyDomain"] = "foreign.myshopify.com"
    pending = SealloConnectionCode.find_by!(digest: Digest::SHA256.hexdigest(code))
    expect { connect }.to raise_error(Connections::ShopifyApi::Error) { |error| expect(error.code).to eq("source_mismatch") }
    expect(store.store_connections).to be_empty
    expect(pending.reload.consumed_at).to be_nil
    expect(ShopifyOrdersSyncJob).not_to have_been_enqueued
  end

  it "rejects missing order scope without requesting unused customer/product/write scopes" do
    verification["currentAppInstallation"]["accessScopes"] = []
    expect { connect }.to raise_error(Connections::ShopifyApi::Error) { |error| expect(error.code).to eq("missing_scopes") }
    expect(store.store_connections).to be_empty
  end

  it "prevents an already linked shop from moving to another workspace" do
    existing = other_store.store_connections.create!(provider: "shopify", external_domain: shop, name: "Other workspace shop", shopify_oauth: true, shopify_app: "seallo_connect")
    expect { connect }.to raise_error(described_class::Error, "already_linked")
    expect(existing.reload.store_id).to eq(other_store.id)
    expect(store.store_connections).to be_empty
  end

  it "keeps a disconnected shop reserved to its original workspace" do
    existing = other_store.store_connections.create!(provider: "shopify", external_domain: shop, name: "Disconnected shop", shopify_oauth: true, shopify_app: "seallo_connect", active: false)
    expect { connect }.to raise_error(described_class::Error, "already_linked")
    expect(existing.reload).not_to be_active
  end

  it "does not replace a legacy connection for the same shop" do
    existing = store.store_connections.create!(provider: "shopify", external_domain: shop, name: "Existing Shopify app", shopify_oauth: true)
    expect { connect }.to raise_error(described_class::Error, "existing_connection")
    expect(existing.reload.shopify_app).to be_nil
    expect(store.store_connections.count).to eq(1)
  end

  it "reconnects the original workspace without creating another import identity" do
    existing = store.store_connections.create!(provider: "shopify", external_domain: shop, name: "Original shop", shopify_oauth: true, shopify_app: "seallo_connect", active: false)
    expect(connect.id).to eq(existing.id)
    expect(existing.reload).to be_active
    expect(store.store_connections.count).to eq(1)
  end

  it "does not issue a workspace code to another workspace's staff" do
    expect { SealloConnectionCode.issue!(store: other_store, user: staff) }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it "rejects malformed codes and nonpermanent shop domains before reaching Shopify" do
    expect(Connections::SealloBridge).not_to receive(:graphql)
    expect { described_class.call(code: "guess", shop: shop) }.to raise_error(described_class::Error, "invalid_code")
    expect { described_class.call(code: code, shop: "https://evil.test") }.to raise_error(described_class::Error, "invalid_shop")
  end
end

RSpec.describe "Concurrent Seallo workspace linking" do
  self.use_transactional_tests = false

  before do
    @suffix = SecureRandom.hex(6)
    @stores = 2.times.map do |index|
      Store.create!(slug: "seallo-race-#{index}-#{@suffix}", name: "Synthetic link race #{index}", currency: "MAD", storefront_enabled: false)
    end
    @staff = @stores.each_with_index.map do |store, index|
      store.users.create!(email: "seallo-race-#{index}-#{@suffix}@example.test", password: "synthetic-race-password-123", admin: true)
    end
    @shop = "race-#{@suffix}.myshopify.com"
    allow(Connections::SealloBridge).to receive(:graphql).and_return(
      "shop" => { "myshopifyDomain" => @shop }, "currentAppInstallation" => { "accessScopes" => [ { "handle" => "read_orders" } ] }
    )
    allow(Connections::SealloBridge).to receive(:entitlement).and_return(
      "active" => true, "current_period_start" => 1.day.ago.iso8601, "current_period_end" => 29.days.from_now.iso8601,
      "plan_name" => "Seallo Basic", "order_limit" => 19
    )
  end

  after do
    SealloConnectionCode.where(store_id: @stores.map(&:id)).delete_all if @stores
    @stores&.each(&:destroy!)
  end

  def race(codes)
    ready = Queue.new
    start = Queue.new
    workers = codes.map do |code|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          start.pop
          begin
            Connections::SealloConnect.call(code: code, shop: @shop)
            "linked"
          rescue Connections::SealloConnect::Error => error
            error.message
          end
        end
      end
    end
    Timeout.timeout(15) do
      codes.length.times { ready.pop }
      codes.length.times { start << true }
      workers.map(&:value)
    end
  ensure
    workers&.each { |worker| worker.kill if worker.alive? }
    workers&.each(&:join)
  end

  it "consumes a single code once when two installations race" do
    code = SealloConnectionCode.issue!(store: @stores.first, user: @staff.first)
    expect(race([ code, code ])).to match_array(%w[linked invalid_code])
    expect(StoreConnection.where(shopify_app: "seallo_connect", external_domain: @shop).count).to eq(1)
    expect(SealloConnectionCode.where(store: @stores.first).where.not(consumed_at: nil).count).to eq(1)
  end

  it "keeps one workspace owner when different workspace codes race for the same shop" do
    codes = @stores.each_with_index.map { |store, index| SealloConnectionCode.issue!(store: store, user: @staff[index]) }
    expect(race(codes)).to match_array(%w[linked already_linked])
    expect(StoreConnection.where(shopify_app: "seallo_connect", external_domain: @shop).count).to eq(1)
    expect(SealloConnectionCode.where(store: @stores).where.not(consumed_at: nil).count).to eq(1)
  end
end
