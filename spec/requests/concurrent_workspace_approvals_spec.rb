# frozen_string_literal: true

require "rails_helper"
require "timeout"

RSpec.describe "Concurrent workspace decisions", type: :request do
  # Worker connections must see committed fixtures. Cleanup is restricted to
  # this example's synthetic request, user and exact generated workspace slugs.
  self.use_transactional_tests = false

  before do
    @suffix = SecureRandom.hex(6)
    @password = "Synthetic-#{@suffix}-password"
    @slugs = [ "decision-a-#{@suffix}", "decision-b-#{@suffix}" ]
    @admin = User.create!(email: "decision-root-#{@suffix}@example.test", password: @password, admin: true, super_admin: true)
    @request = AccessRequest.create!(store_name: "Synthetic decision #{@suffix}", email: "decision-#{@suffix}@example.test", storefront_enabled: false)
    @clients = 2.times.map do
      ActionDispatch::Integration::Session.new(Rails.application).tap do |client|
        client.host! Store.base_domain
        client.post "/admin/login", params: { email: @admin.email, password: @password }
        expect(client.response).to have_http_status(:redirect)
      end
    end
  end

  after do
    @request&.destroy!
    Store.where(slug: @slugs).find_each(&:destroy!) if @slugs
    @admin&.destroy!
  end

  def approval(index)
    { access_request_id: @request.id,
      store: { name: @request.store_name, slug: @slugs[index], currency: "MAD", storefront_enabled: false },
      admin: { email: "decision-staff-#{index}-#{@suffix}@example.test", password: @password } }
  end

  def race(&action)
    ready = Queue.new
    start = Queue.new
    workers = @clients.each_with_index.map do |client, index|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          start.pop
          action.call(client, index)
          client.response.status
        end
      end
    end
    Timeout.timeout(15) do
      2.times { ready.pop }
      2.times { start << true }
      workers.map(&:value)
    end
  ensure
    workers&.each { |worker| worker.kill if worker.alive? }
    workers&.each(&:join)
  end

  it "creates one workspace when two admins approve the same request simultaneously" do
    statuses = race { |client, index| client.post "/admin/tenants", params: approval(index) }

    expect(statuses).to all(eq(302))
    expect(Store.where(slug: @slugs).count).to eq(1)
    expect(@request.reload.status).to eq("approved")
    expect(@request.store.slug).to be_in(@slugs)
    expect(User.where(email: 2.times.map { |index| "decision-staff-#{index}-#{@suffix}@example.test" }).count).to eq(1)
  end

  it "keeps the request and workspace consistent when approval races with rejection" do
    statuses = race do |client, index|
      if index.zero?
        client.post "/admin/tenants", params: approval(index)
      else
        client.post "/admin/access_requests/#{@request.id}/reject"
      end
    end

    expect(statuses).to all(eq(302))
    @request.reload
    if @request.status == "approved"
      expect(Store.where(slug: @slugs).pluck(:id)).to eq([ @request.store_id ])
    else
      expect(@request.status).to eq("rejected")
      expect(@request.store_id).to be_nil
      expect(Store.where(slug: @slugs)).to be_empty
    end
  end
end
