# MCP management coverage

This assessment compares existing app controllers, GraphQL fields and registered MCP tools. It is not a claim of Shopify feature parity or of live plugin availability.

| App area | Backend MCP coverage | Remaining work |
| --- | --- | --- |
| Products, collections, variants | Create, read, update, delete and assignment | Verify cross-store isolation and deployed tool discovery |
| Images | Upload, remove, reorder, collection cover; image URLs and cover previews | Gallery preview changes prepared locally; verify ChatGPT rendering after deployment |
| Inventory | Levels, low stock, movements, adjustments | Run integration checks and verify discovery |
| Customers | List, detail, upsert | Compare all admin fields and enforce customer data access policy |
| Orders | List, detail, reporting, cancellation | Create/edit/duplicate, transitions, archive/unarchive, comments/tags, packing slips, Sendit actions and labels are admin features without corresponding MCP tools |
| Discounts, shipping, checkout, marketing | Read/update tools and shipping synchronization | Verify per-setting field coverage and deployed behavior |
| Storefront content | Pages, menus, home sections, landing page/layout builders | Verify preview and publish behavior against admin workflows |
| Imports and exports | CSV import/export | Verify size limits, validation and failure reporting |
| Brand and catalog autonomy | Profile, audit, suggestions, preview/apply/verify/rollback | Connected plugin currently exposes a subset of the repository's registered tools |
| Media transformations | Admin crop, background removal and watermark | No corresponding MCP transformation tools identified |
| Staff | Admin staff CRUD | Needs dedicated authorized staff-management capabilities; store catalog tokens must not silently acquire platform privileges |
| Platform tenants and billing | Admin tenant and invoice workflows | Needs separate platform authorization before exposing tenant creation, invoices and billing actions |
| OAuth | Discovery, dynamic registration, PKCE, exchange and refresh | Hardenings prepared locally; full fresh ChatGPT authorization still needs interactive verification |
| Automation | Existing shipping jobs; new health/reporting and CI files | Branch pushed after GitHub access update; deployment awaits passing CI. Reports require a securely configured Actions token |

## Acceptance criteria for full existing-app management

1. Each supported admin operation has a documented MCP capability, validation rules and response schema.
2. Reuse existing domain services, including Orders::Editor and Order transitions, rather than bypassing inventory and order lifecycle rules.
3. All store operations scope identifiers to the authenticated store. Platform actions require a separately authenticated platform role.
4. Destructive and financially material actions preserve explicit confirmation and existing approval levels.
5. Tests cover successful operations, invalid inputs, cross-store access, token expiration/revocation and rollback where supported.
6. Product responses identify each image by product slug, position, filename and URL; attached previews have explicit limits and failures.
7. OAuth discovery, consent, PKCE exchange, refresh and MCP access are verified against the deployed service and a fresh ChatGPT connection.
8. Compare deployed tools/list with the intended backend manifest and then refresh the ChatGPT plugin's tool discovery.

## Blocking conditions

GitHub repository writes were initially denied with HTTP 403 and became available after the user updated access. The changes are on a pull request, pending CI and deployment verification. Repository Actions secret access still returns HTTP 403; the scheduled report needs MOREA_API_TOKEN configured securely in repository Actions secrets.

The phrase “copy of Shopify” does not define a finite additional feature set. Payments, refunds, tax jurisdictions, markets, subscriptions, POS, app integrations and other Shopify capabilities require explicit requirements and provider choices; these were not established or implemented by this assessment.
