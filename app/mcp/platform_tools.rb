# frozen_string_literal: true

module PlatformTools
  class Unauthorized < StandardError; end

  PAGE_PROPERTIES = {
    after_id: { type: "integer", minimum: 0, description: "Return IDs greater than this cursor" },
    limit: { type: "integer", minimum: 1, maximum: 100, description: "Default 50" }
  }.freeze
  TENANT_FIELDS = %w[id name slug currency storefront_enabled billing_status billing_interval billing_amount_cents billing_period_ends_on].freeze
  USER_FIELDS = %w[id store_id name status admin super_admin confirmation_role].freeze
  INVOICE_FIELDS = %w[id store_id number status amount_cents billing_interval period_starts_on period_ends_on due_on issued_at paid_at].freeze

  def self.authorize!(user)
    actor = User.find_by(id: user&.id)
    raise Unauthorized, "Active superadmin required" unless actor&.active? && actor.super_admin?

    actor
  end

  def self.run(context)
    actor = authorize!(context.fetch(:user))
    payload = yield actor
    MCP::Tool::Response.new([ { type: "text", text: JSON.generate(payload) } ])
  rescue Unauthorized
    error("Active superadmin required")
  rescue ActiveRecord::RecordNotFound
    error("Record not found")
  rescue ActiveRecord::RecordInvalid
    error("Invalid state transition or record")
  rescue Platform::UserLifecycle::Denied => e
    error("User lifecycle denied: #{e.reason}")
  rescue ArgumentError => e
    error(e.message)
  end

  def self.error(message)
    MCP::Tool::Response.new([ { type: "text", text: JSON.generate(error: message) } ], error: true)
  end

  def self.page(scope, fields, after_id:, limit:)
    raise ArgumentError, "limit must be between 1 and 100" unless limit.is_a?(Integer) && limit.between?(1, 100)
    raise ArgumentError, "after_id must be non-negative" unless after_id.is_a?(Integer) && after_id >= 0

    rows = scope.where("id > ?", after_id).order(:id).limit(limit + 1).to_a
    more = rows.length > limit
    rows = rows.first(limit)
    { records: rows.map { |row| row.slice(*fields) }, next_after_id: more ? rows.last.id : nil }
  end

  def self.confirm!(confirm)
    raise ArgumentError, "Explicit confirmation required" unless confirm == true
  end

  class ListTenants < MCP::Tool
    description "List platform workspaces and subscription settings, without credentials or customer data. Cursor pagination."
    input_schema(properties: PAGE_PROPERTIES)

    def self.call(server_context:, after_id: 0, limit: 50)
      PlatformTools.run(server_context) do
        PlatformTools.page(Store.all, TENANT_FIELDS, after_id: after_id, limit: limit)
      end
    end
  end

  class ListPlatformUsers < MCP::Tool
    description "List staff accounts, roles and lifecycle status. Optionally filter by tenant. Omits passwords, tokens and email addresses."
    input_schema(properties: PAGE_PROPERTIES.merge(tenant_id: { type: "integer" }))

    def self.call(server_context:, tenant_id: nil, after_id: 0, limit: 50)
      PlatformTools.run(server_context) do
        scope = tenant_id ? Store.find(tenant_id).users : User.all
        PlatformTools.page(scope, USER_FIELDS, after_id: after_id, limit: limit)
      end
    end
  end

  class ListTenantInvoices < MCP::Tool
    description "List one tenant's platform subscription invoices. Amounts are integer cents, not merchant revenue."
    input_schema(properties: PAGE_PROPERTIES.merge(tenant_id: { type: "integer" }), required: [ "tenant_id" ])

    def self.call(server_context:, tenant_id:, after_id: 0, limit: 50)
      PlatformTools.run(server_context) do
        store = Store.find(tenant_id)
        PlatformTools.page(store.invoices, INVOICE_FIELDS, after_id: after_id, limit: limit).merge(currency: store.currency)
      end
    end
  end

  class TransitionPlatformUser < MCP::Tool
    description "Suspend, reactivate, archive or restore a staff account using platform lifecycle safeguards. Requires explicit user approval and confirm: true."
    input_schema(properties: {
      user_id: { type: "integer" },
      action: { type: "string", enum: %w[suspend reactivate archive restore] },
      confirm: { type: "boolean" }
    }, required: %w[user_id action confirm])

    def self.call(server_context:, user_id:, action:, confirm: false)
      PlatformTools.run(server_context) do |actor|
        PlatformTools.confirm!(confirm)
        user = User.find(user_id)
        Platform::UserLifecycle.new(user: user, actor: actor).call(action)
        user.reload.slice(*USER_FIELDS)
      end
    end
  end

  class TransitionTenantInvoice < MCP::Tool
    description "Issue, mark paid or void a tenant subscription invoice. Requires explicit user approval and confirm: true. Mark paid records an externally verified payment and activates billing; it does not collect money."
    input_schema(properties: {
      tenant_id: { type: "integer" }, invoice_id: { type: "integer" },
      action: { type: "string", enum: %w[issue mark_paid void] },
      confirm: { type: "boolean" }
    }, required: %w[tenant_id invoice_id action confirm])

    def self.call(server_context:, tenant_id:, invoice_id:, action:, confirm: false)
      PlatformTools.run(server_context) do
        PlatformTools.confirm!(confirm)
        raise ArgumentError, "Unknown invoice action" unless %w[issue mark_paid void].include?(action)

        store = Store.find(tenant_id)
        store.with_lock do
          invoice = store.invoices.lock.find(invoice_id)
          invoice.public_send("#{action}!")
          invoice.reload.slice(*INVOICE_FIELDS).merge(currency: store.currency)
        end
      end
    end
  end
end
