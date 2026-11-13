# frozen_string_literal: true

require "rails_helper"
require "timeout"

RSpec.describe "Concurrent platform admin changes", type: :request do
  self.use_transactional_tests = false

  before do
    suffix = SecureRandom.hex(6)
    password = "Synthetic-#{suffix}-password"
    @store = Store.create!(slug: "admin-race-#{suffix}", name: "Synthetic admin race", currency: "MAD")
    @admins = 2.times.map do |index|
      User.create!(email: "admin-race-#{index}-#{suffix}@example.test", password: password, admin: true, super_admin: true)
    end
    @clients = @admins.map do |admin|
      ActionDispatch::Integration::Session.new(Rails.application).tap do |client|
        client.host! Store.base_domain
        client.post "/admin/login", params: { email: admin.email, password: password }
        expect(client.response).to have_http_status(:redirect)
      end
    end
    # Isolate the last-admin invariant without changing seeded administrator
    # records. Both requests still use real committed rows and PostgreSQL locks.
    ids = @admins.map(&:id)
    allow(User).to receive(:super_admins).and_wrap_original { |original| original.call.where(id: ids) }
  end

  after do
    @workers&.each { |worker| worker.kill if worker.alive? }
    @workers&.each(&:join)
    @admins&.each(&:destroy!)
    @store&.destroy!
  end

  it "keeps an active super admin when demotion races with suspension" do
    checked = Queue.new
    release = Queue.new
    suspended = Queue.new
    allow_any_instance_of(Admin::PlatformUsersController).to receive(:demotion_denied_reason).and_wrap_original do |original|
      reason = original.call
      checked << true
      release.pop
      reason
    end

    @workers = [ Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        @clients[0].patch "/admin/platform/users/#{@admins[1].id}", params: {
          user: { email: @admins[1].email, role: "workspace_admin", store_id: @store.id }
        }
        @clients[0].response.status
      end
    end ]

    statuses = Timeout.timeout(15) do
      # Both accounts are still active when the demotion guard has passed.
      checked.pop
      @workers << Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          @clients[1].post "/admin/platform/users/#{@admins[0].id}/lifecycle/suspend"
          suspended << true
          @clients[1].response.status
        end
      end

      # With locking, suspension waits for the demotion transaction. Before the
      # fix it completes first, allowing the pending demotion to remove the last
      # active super admin. Wait for either state instead of relying on timing.
      loop do
        waiting = ActiveRecord::Base.connection.select_value(<<~SQL)
          SELECT EXISTS (
            SELECT 1 FROM pg_stat_activity
            WHERE datname = current_database()
              AND pid <> pg_backend_pid()
              AND wait_event_type = 'Lock'
              AND query LIKE '%"users"%'
          )
        SQL
        break if !suspended.empty? || waiting
        sleep 0.01
      end
      release << true
      @workers.map(&:value)
    end

    expect(statuses).to eq([ 302, 302 ])
    expect(User.where(id: @admins.map(&:id), super_admin: true, status: "active").count).to eq(1)
  ensure
    release << true
  end
end
