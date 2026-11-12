# frozen_string_literal: true

module Platform
  # Actionable items for the unified Super Admin overview. Each item deep-links
  # to the record that needs attention.
  class ActionQueue
    ZONE = DashboardSummary::ZONE
    LIST_LIMIT = 10

    Item = Struct.new(:kind, :title, :detail, :path, :tone, :record, keyword_init: true)

    attr_reader :overdue_invoices, :pending_access_requests, :integration_failures, :privacy_requests, :items

    def initialize(now: Time.current)
      @now = now.in_time_zone(ZONE)
      @overdue_invoices = Invoice.open_issued.where("due_on < ?", @now.to_date)
        .includes(:store).order(:due_on, :id).limit(LIST_LIMIT).to_a
      @pending_access_requests = AccessRequest.pending.order(created_at: :asc).limit(LIST_LIMIT).to_a
      @integration_failures = failing_connections
      @privacy_requests = PlatformPrivacyRightsRequest.where(status: "open").order(created_at: :asc).limit(LIST_LIMIT).to_a
      @items = build_items
    end

    private

    def failing_connections
      StoreConnection.includes(:store).where(active: true)
        .where.not(shopify_api_error_code: [ nil, "" ])
        .order(updated_at: :desc).limit(LIST_LIMIT).to_a
    end

    def build_items
      overdue_items + access_items + integration_items + privacy_items
    end

    def overdue_items
      @overdue_invoices.map do |invoice|
        Item.new(
          kind: "overdue_invoice",
          title: invoice.number,
          detail: "#{invoice.store.name} · due #{invoice.due_on}",
          path: [ :admin_tenant_invoice, invoice.store, invoice ],
          tone: "critical",
          record: invoice
        )
      end
    end

    def access_items
      @pending_access_requests.map do |request|
        Item.new(
          kind: "access_request",
          title: request.store_name,
          detail: request.email,
          path: [ :admin_access_requests, { status: "pending" } ],
          tone: "attention",
          record: request
        )
      end
    end

    def integration_items
      @integration_failures.map do |connection|
        Item.new(
          kind: "integration_failure",
          title: "#{connection.provider} · #{connection.external_domain}",
          detail: "#{connection.store.name} · #{connection.shopify_api_error_code}",
          path: [ :admin_platform_integration, connection.store ],
          tone: "warning",
          record: connection
        )
      end
    end

    def privacy_items
      @privacy_requests.map do |request|
        Item.new(
          kind: "privacy_request",
          title: request.request_type.to_s.humanize,
          detail: request.requester_contact.to_s,
          path: [ :admin_platform_privacy_rights_request, request ],
          tone: "attention",
          record: request
        )
      end
    end
  end
end
