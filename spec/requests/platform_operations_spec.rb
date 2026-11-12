# frozen_string_literal: true

require "rails_helper"
require "nokogiri"
require "sidekiq/api"

RSpec.describe "Platform operations console", type: :request do
  let(:password) { "synthetic-platform-operations-password-123" }
  let!(:super_admin) do
    User.create!(
      email: "platform-ops-#{SecureRandom.hex(5)}@example.test",
      password: password,
      admin: true,
      super_admin: true
    )
  end
  let!(:store) do
    Store.create!(
      slug: "po-#{SecureRandom.hex(5)}",
      name: "Platform ops workspace",
      currency: "MAD"
    )
  end
  let!(:merchant) do
    store.users.create!(
      email: "platform-ops-merchant-#{SecureRandom.hex(5)}@example.test",
      password: password,
      admin: true
    )
  end
  let!(:failing_connection) do
    store.store_connections.create!(
      provider: "shopify",
      name: "Ops failing shop",
      external_domain: "ops-#{SecureRandom.hex(5)}.myshopify.com",
      shopify_app: "seallo_connect",
      shopify_oauth: true,
      shopify_api_error_code: "invalid_credentials"
    )
  end

  before { host! Store.base_domain }

  def sign_in(user)
    post "/admin/login", params: { email: user.email, password: password }
    expect(response).to have_http_status(:redirect)
  end

  def stub_job_sets(dead: [], retry_jobs: [])
    dead_set = instance_double(Sidekiq::DeadSet)
    retry_set = instance_double(Sidekiq::RetrySet)
    allow(dead_set).to receive(:first).and_return(dead)
    allow(retry_set).to receive(:first).and_return(retry_jobs)
    allow(Sidekiq::DeadSet).to receive(:new).and_return(dead_set)
    allow(Sidekiq::RetrySet).to receive(:new).and_return(retry_set)
    dead_set
  end

  it "requires authentication and rejects merchant administrators" do
    get "/admin/platform/operations"
    expect(response).to redirect_to(admin_login_path)

    host! "#{store.slug}.#{Store.base_domain}"
    sign_in(merchant)
    host! Store.base_domain
    get "/admin/platform/operations"
    expect(response).to redirect_to(admin_root_path)
  end

  it "shows connection error codes and empty job lists when Redis is unavailable" do
    allow(Sidekiq::DeadSet).to receive(:new).and_raise(Errno::ECONNREFUSED)

    sign_in(super_admin)
    get "/admin/platform/operations"

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    expect(document.at_css('[data-redis-unavailable="true"]')).to be_present
    expect(document.at_css("[data-platform-operations-dead]")).to be_present
    expect(document.at_css("[data-platform-operations-retry]")).to be_present
    expect(response.body).to include(I18n.t("platform_admin.operations.empty_jobs"))
    expect(response.body).to include(I18n.t("platform_admin.operations.empty_retry"))
    expect(document.at_css(%([data-connection-id="#{failing_connection.id}"][data-error-code="invalid_credentials"]))).to be_present
    expect(response.body).to include(store.name, "invalid_credentials")
  end

  it "attributes failed jobs to a workspace when args include store_id" do
    job = double(
      "sidekiq-job",
      jid: "jid-synthetic-1",
      display_class: "SenditCitiesRefreshJob",
      queue: "default",
      args: [ { "store_id" => store.id } ],
      item: {
        "error_message" => "synthetic failure",
        "failed_at" => Time.current.to_f
      },
      score: Time.current.to_f
    )
    stub_job_sets(dead: [ job ])

    sign_in(super_admin)
    get "/admin/platform/operations"

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    expect(document.at_css('[data-job-set="dead"][data-job-class="SenditCitiesRefreshJob"][data-job-orphan="false"]')).to be_present
    expect(response.body).to include("SenditCitiesRefreshJob", "synthetic failure", store.name)
    expect(document.at_css('[data-redis-unavailable="true"]')).to be_nil
  end

  it "marks missing classes as orphans and clears them after confirmation" do
    orphan = double(
      "sidekiq-orphan",
      jid: "jid-orphan-1",
      display_class: "RebuildBusinessSearchIndexJob",
      queue: "default",
      args: [],
      item: {
        "error_message" => "Failed to instantiate job",
        "failed_at" => Time.current.to_f
      },
      score: Time.current.to_f
    )
    dead_set = stub_job_sets(dead: [ orphan ])
    allow(dead_set).to receive(:each).and_yield(orphan)
    allow(orphan).to receive(:delete)

    sign_in(super_admin)
    get "/admin/platform/operations"
    document = Nokogiri::HTML(response.body)
    expect(document.at_css('[data-job-orphan="true"][data-job-class="RebuildBusinessSearchIndexJob"]')).to be_present
    expect(document.at_css('[data-orphan-jobs="1"]')).to be_present

    expect {
      delete clear_orphans_admin_platform_operations_path
    }.to change(AuditEvent, :count).by(1)

    expect(response).to redirect_to(admin_platform_operations_path)
    follow_redirect!
    expect(response.body).to include(I18n.t("platform_admin.operations.cleared_orphans", count: 1))
    expect(orphan).to have_received(:delete)
    expect(AuditEvent.order(:id).last.action).to eq("platform.operations.clear_dead_jobs")
  end

  it "clears the whole dead set" do
    dead_set = stub_job_sets
    allow(dead_set).to receive(:size).and_return(3)
    allow(dead_set).to receive(:clear)

    sign_in(super_admin)
    expect {
      delete clear_dead_admin_platform_operations_path
    }.to change(AuditEvent, :count).by(1)

    expect(response).to redirect_to(admin_platform_operations_path)
    expect(dead_set).to have_received(:clear)
  end

  it "deletes one dead job by jid" do
    job = double("sidekiq-job-delete", jid: "jid-delete-1")
    dead_set = stub_job_sets
    allow(dead_set).to receive(:find_job).with("jid-delete-1").and_return(job)
    allow(job).to receive(:delete)

    sign_in(super_admin)
    delete destroy_dead_admin_platform_operations_path(jid: "jid-delete-1")

    expect(response).to redirect_to(admin_platform_operations_path)
    expect(job).to have_received(:delete)
  end
end
