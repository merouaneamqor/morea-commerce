# frozen_string_literal: true

require "rails_helper"

RSpec.describe "MetaAds models" do
  def new_store(prefix = "meta")
    Store.create!(slug: "#{prefix}-#{SecureRandom.hex(5)}", name: "Synthetic #{prefix}", currency: "MAD")
  end

  def connect(store, token: "synthetic-meta-token")
    MetaAds::Connection.create!(store: store, access_token: token)
  end

  def ad_account(store, connection, id: "act_1001", selected: true)
    MetaAds::AdAccount.create!(store: store, connection: connection, meta_ad_account_id: id, name: "Synthetic", currency: "EUR", timezone_name: "Europe/Paris", selected: selected)
  end

  let(:store) { new_store }
  let(:connection) { connect(store) }

  describe MetaAds::Connection do
    it "encrypts the token and never exposes it through inspect or serialization" do
      expect(connection.access_token).to eq("synthetic-meta-token")
      expect(connection.access_token_ciphertext).not_to include("synthetic-meta-token")
      expect(connection.inspect).not_to include("synthetic-meta-token")
      expect(connection.inspect).not_to include(connection.access_token_ciphertext)
      expect(connection.as_json.to_s).not_to include("synthetic-meta-token")
      expect(connection.as_json.keys).not_to include("access_token_ciphertext", "oauth_state_digest")
    end

    it "allows one connection per store, so reconnecting updates the existing row" do
      connection
      expect { MetaAds::Connection.create!(store: store, access_token: "other") }.to raise_error(ActiveRecord::RecordInvalid)
      connection.update!(status: "needs_reauthorization")
      connection.update!(status: "active", access_token: "synthetic-new-token")
      expect(MetaAds::Connection.where(store: store).count).to eq(1)
      expect(connection.reload.access_token).to eq("synthetic-new-token")
    end

    it "requires a token while active" do
      expect(MetaAds::Connection.new(store: new_store, status: "active")).not_to be_valid
    end

    it "stops syncing and keeps history when authorization is lost" do
      account = ad_account(store, connection)
      account.campaigns.create!(store: store, meta_id: "1", name: "History")
      connection.mark_needs_reauthorization!("invalid_token")

      expect(connection.reload).to have_attributes(status: "needs_reauthorization", access_token: nil, last_error_code: "invalid_token")
      expect(account.reload.sync_status).to eq("needs_reauthorization")
      expect(account.campaigns.count).to eq(1)
    end

    it "removes the token and unselects accounts on disconnect without deleting history" do
      account = ad_account(store, connection)
      connection.disconnect!

      expect(connection.reload).to have_attributes(status: "disconnected", access_token: nil)
      expect(account.reload.selected).to be(false)
    end
  end

  describe MetaAds::AdAccount do
    it "rejects malformed ids and an account owned by another store's connection" do
      expect(MetaAds::AdAccount.new(store: store, connection: connection, meta_ad_account_id: "1001")).not_to be_valid
      other_store = new_store("other")
      expect(MetaAds::AdAccount.new(store: other_store, connection: connection, meta_ad_account_id: "act_5")).not_to be_valid
    end

    it "does not let one ad account be selected by two stores" do
      ad_account(store, connection, id: "act_2002")
      other_store = new_store("other")
      other_connection = connect(other_store)

      expect { ad_account(other_store, other_connection, id: "act_2002") }.to raise_error(ActiveRecord::RecordNotUnique)
      expect(ad_account(other_store, other_connection, id: "act_2002", selected: false)).to be_persisted
    end
  end

  describe "cached structure and insights" do
    let(:account) { ad_account(store, connection) }

    it "upserts are unique per ad account and Meta id" do
      account.campaigns.create!(store: store, meta_id: "c1")
      expect(account.campaigns.build(store: store, meta_id: "c1")).not_to be_valid
    end

    it "refuses children that point at another store's records" do
      other_store = new_store("other")
      other_account = ad_account(other_store, connect(other_store), id: "act_3003")
      foreign_campaign = other_account.campaigns.create!(store: other_store, meta_id: "c9")

      expect(account.ad_sets.build(store: store, meta_id: "s1", campaign: foreign_campaign)).not_to be_valid
      expect(account.campaigns.build(store: other_store, meta_id: "c2")).not_to be_valid
      expect {
        MetaAds::Campaign.new(store: other_store, ad_account: account, meta_id: "c3").save!(validate: false)
      }.to raise_error(ActiveRecord::InvalidForeignKey)
    end

    it "keeps one insight row per account, campaign and day" do
      campaign = account.campaigns.create!(store: store, meta_id: "c1")
      attrs = { store: store, ad_account: account, campaign: campaign, level: "campaign", date: Date.new(2026, 10, 1), currency: "EUR", synced_at: Time.current }
      MetaAds::DailyInsight.create!(attrs)

      expect { MetaAds::DailyInsight.new(attrs).save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "requires a campaign only at campaign level and rejects negative spend" do
      base = { store: store, ad_account: account, date: Date.new(2026, 10, 1), currency: "EUR", synced_at: Time.current }
      expect(MetaAds::DailyInsight.new(base.merge(level: "campaign"))).not_to be_valid
      expect(MetaAds::DailyInsight.new(base.merge(level: "account", spend: -1))).not_to be_valid
      expect(MetaAds::DailyInsight.create!(base.merge(level: "account", spend: 12.5))).to be_persisted
    end
  end
end
