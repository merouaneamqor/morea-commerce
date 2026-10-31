# Superadmin MCP

The platform MCP server is separate from the existing `/mcp` catalog server. A store's catalog token must never grant platform access. Platform tools re-read the authenticated user on every call and require an active superadmin, including platform-only users without a home store. Revoking a user's platform role or suspending/archiving the user prevents subsequent calls.

## Initial capabilities

| Tool | Inputs | Result |
| --- | --- | --- |
| `list_tenants` | optional `after_id`, `limit` | Workspace identity, storefront setting, currency and subscription settings |
| `list_platform_users` | optional `tenant_id`, `after_id`, `limit` | Staff identity, tenant, role and lifecycle status |
| `list_tenant_invoices` | `tenant_id`; optional `after_id`, `limit` | Subscription invoices and tenant currency |
| `transition_platform_user` | `user_id`, `action`, `confirm` | Updated staff status |
| `transition_tenant_invoice` | `tenant_id`, `invoice_id`, `action`, `confirm` | Updated invoice and tenant currency |

Lists return `{records, next_after_id}` with a default page size of 50 and maximum of 100. Pass `next_after_id` as `after_id` for the next page; null means there are no more results. IDs are ordered ascending. Results deliberately omit credentials, API tokens, password digests, customer details and staff email addresses. Monetary amounts use integer cents.

All tools return JSON in MCP text content. Expected authorization, missing-record, validation, confirmation and transition failures return an MCP tool error rather than a successful result.

## Mutations

Before a mutation, read the target record, explain the exact intended change and obtain the user's explicit approval. Pass `confirm: true` only for that approved action.

Staff actions are `suspend`, `reactivate`, `archive`, and `restore`. The existing platform lifecycle service preserves self-suspension and last-active-superadmin safeguards. No password changes, account creation or role elevation is exposed.

Invoice actions are `issue`, `mark_paid`, and `void`. These reuse existing invoice transitions. An invoice is looked up under the specified tenant, and the store and invoice are locked during transition. `mark_paid` requires a previously issued invoice and records a manually verified payment; it activates the tenant subscription and extends its billing period through existing model behavior. It does not charge a provider. Invoice creation and changes to prices or subscription settings remain in platform administration.

## Boundaries and verification

These are platform operations, not a replacement for tenant order/catalog tools. Existing store OAuth grants and catalog authentication remain scoped to one store. Clients must connect separately to the platform endpoint with its separate platform credential.

Verify tool discovery, normal reads, denied merchant access, suspended/demoted actors, missing confirmation, lifecycle safeguards, cross-tenant invoice IDs and invoice state transitions against an isolated test database. Deployment and a fresh client connection are separate from local verification.

## Connect with OAuth

After deploying and running `bin/rails db:migrate`, add `https://ollazen.com/platform/mcp` to an OAuth-capable Streamable HTTP MCP client. Sign in as a superadmin and approve the named client on the platform consent page. No tenant selection is required. The store `/mcp` endpoint and its OAuth flow remain separate.

The endpoint advertises `/.well-known/oauth-protected-resource/platform/mcp` in its authentication challenge. Platform authorization-server discovery is at `/.well-known/oauth-authorization-server/platform/oauth`, with issuer `/platform/oauth`, authorization `/platform/oauth/authorize` and token `/platform/oauth/token`. Dynamic client registration reuses `/oauth/register`. The only platform scope is `platform`; authorization codes use S256 PKCE and expire after ten minutes. Codes are database-backed, single-use and bound to the user, client, exact redirect URI and platform resource.

Access tokens expire after one hour. Refresh tokens expire after 90 days and rotate atomically; previous access and refresh tokens are revoked on rotation. All secrets are stored as digests. Suspended, archived or demoted owners cannot exchange, refresh or use grants. Store tokens cannot access platform tools and platform tokens cannot access store tools.

Open **Superadmin MCP** in the platform sidebar (`/admin/platform/agent-api`) to revoke agent connections, including pending authorization codes. Existing manual platform tokens remain available under the advanced section and have a separate revoke control.

Focused checks: `RAILS_ENV=test bundle exec rspec spec/models/platform_oauth_spec.rb spec/requests/platform_oauth_spec.rb spec/models/platform_api_token_spec.rb spec/requests/platform_mcp_spec.rb spec/mcp/platform_tools_spec.rb` with an isolated test PostgreSQL database. A fresh client authorization after deployment is still required to verify the hosted connection.
