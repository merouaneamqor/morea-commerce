require 'rails_helper'

RSpec.describe 'Advertising dashboard', type: :request do
  let(:store) { Store.create!(slug: "ad-#{SecureRandom.hex(5)}", name: 'Synthetic ads', currency: 'MAD') }
  let(:account) { AdvertisingAccount.create!(store: store, name: 'Main', provider: 'Meta') }
  let(:campaign) { account.advertising_campaigns.create!(name: 'Synthetic campaign') }

  def sign_in
    user = store.users.create!(email: "ads-#{SecureRandom.hex(4)}@example.test", password: 'synthetic-password-123', admin: true)
    host! "#{store.slug}.#{Store.base_domain}"
    post '/admin/login', params: { email: user.email, password: 'synthetic-password-123' }
  end

  it 'requires authentication' do
    host! "#{store.slug}.#{Store.base_domain}"
    get '/admin/advertising'
    expect(response).to redirect_to(admin_login_path)
  end

  it 'renders empty states and loads exact daily totals for editing' do
    sign_in
    get '/admin/advertising'
    expect(response).to have_http_status(:ok)
    campaign.advertising_performances.create!(date: Date.current, spend_cents: 12345)
    get '/admin/advertising', params: { report_campaign_id: campaign.id, report_date: Date.current }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('123.45', 'Synthetic campaign')
  end

  it 'persists exact MAD amounts and replaces rather than duplicates a campaign day' do
    sign_in
    data = { advertising_campaign_id: campaign.id, date: Date.current, spend: '12.34', delivered_revenue: '100.01', fulfillment_cost: '20.00', clicks: 5, impressions: 20, confirmed_orders: 2, delivered_orders: 1 }
    2.times { post '/admin/advertising/performance', params: { performance: data } }
    expect(campaign.advertising_performances.count).to eq(1)
    expect(campaign.advertising_performances.first.spend_cents).to eq(1234)
    expect(AdvertisingSummary.new(store: store).profit(AdvertisingSummary.new(store: store).totals)).to eq(6767)
    post '/admin/advertising/performance', params: { performance: data.merge(spend: '-1') }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(campaign.advertising_performances.first.spend_cents).to eq(1234)
  end

  it 'denies foreign campaigns for reporting, edit loads and status updates' do
    sign_in
    foreign_store = Store.create!(slug: "foreign-#{SecureRandom.hex(5)}", name: 'Foreign')
    foreign_account = AdvertisingAccount.create!(store: foreign_store, name: 'Foreign secret', provider: 'Meta')
    foreign_campaign = foreign_account.advertising_campaigns.create!(name: 'Foreign campaign')
    get '/admin/advertising'
    expect(response.body).not_to include('Foreign secret')
    patch "/admin/advertising/campaigns/#{foreign_campaign.id}", params: { active: false }
    expect(response).to have_http_status(:not_found)
    post '/admin/advertising/performance', params: { performance: { advertising_campaign_id: foreign_campaign.id, date: Date.current } }
    expect(response).to have_http_status(:not_found)
    get '/admin/advertising', params: { report_campaign_id: foreign_campaign.id, report_date: Date.current }
    expect(response).to have_http_status(:not_found)
  end

  it 'creates reporting accounts and campaigns, and toggles only their local status' do
    sign_in
    post '/admin/advertising/accounts', params: { account: { name: 'Synthetic new account', provider: 'Meta' } }
    expect(response).to redirect_to(admin_advertising_path)
    created_account = AdvertisingAccount.find_by!(store: store, name: 'Synthetic new account')
    post '/admin/advertising/campaigns', params: { campaign: { advertising_account_id: created_account.id, name: 'Synthetic launch' } }
    created_campaign = created_account.advertising_campaigns.find_by!(name: 'Synthetic launch')
    patch "/admin/advertising/accounts/#{created_account.id}", params: { active: false }
    expect(created_account.reload.active?).to be(false)
    patch "/admin/advertising/campaigns/#{created_campaign.id}", params: { active: false }
    expect(created_campaign.reload.active?).to be(false)
    patch "/admin/advertising/campaigns/#{created_campaign.id}", params: { active: true }
    expect(created_campaign.reload.active?).to be(true)
    post '/admin/advertising/accounts', params: { account: { name: '', provider: 'Unsupported' } }
    expect(response).to have_http_status(:unprocessable_entity)
  end

  %w[en fr ar].each do |locale|
    it "renders reporting in #{locale}" do
      sign_in
      get '/admin/advertising', params: { locale: locale }
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to match(/translation missing|translation_missing/i)
    end
  end

  it 'filters dates and never loses historical data when paused' do
    campaign.advertising_performances.create!(date: Date.current, spend_cents: 100)
    campaign.advertising_performances.create!(date: Date.current - 60, spend_cents: 500)
    campaign.update!(active: false)
    expect(AdvertisingSummary.new(store: store).totals[:spend_cents]).to eq(100)
  end
end
