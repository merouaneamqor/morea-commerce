# frozen_string_literal: true

class PlatformServer
  TOOLS = [
    PlatformTools::ListTenants, PlatformTools::ListPlatformUsers,
    PlatformTools::ListTenantInvoices, PlatformTools::TransitionPlatformUser,
    PlatformTools::TransitionTenantInvoice
  ].freeze

  def self.build(user:)
    PlatformTools.authorize!(user)
    MCP::Server.new(
      name: "morea-superadmin",
      title: "Morea platform administration",
      version: "1.0.0",
      instructions: "Manage platform tenants, staff lifecycle and subscription invoices. This is separate from the store catalog server. Read the target first and obtain explicit user approval before setting confirm: true on mutations. Amounts are integer cents. Never infer payment from merchant order revenue. Invoice mark_paid records a manually verified payment; it does not charge a payment provider.",
      tools: TOOLS,
      server_context: { user: user }
    )
  end
end
