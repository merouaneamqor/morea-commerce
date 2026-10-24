# Morea Commerce development

Morea is a Rails 8 tenant commerce application. A tenant is a merchant workspace; its public storefront is optional (`storefront_enabled`). Preserve existing published storefronts, catalog, cart and COD checkout. External-only workspaces use authenticated operations and connected stores without publishing public shopping routes. The apex hosts platform administration. Read `README.md` and the relevant source before changing behavior.

## Local skills

Use these repository skills when their scope applies:

- `.agents/skills/morea-tenant-commerce/SKILL.md`: tenant hosts, public shopping, localization and authorization boundaries.
- `.agents/skills/morea-cod-operations/SKILL.md`: order intake, confirmation, inventory, carrier and money workflows.
- `.agents/skills/morea-feature-delivery/SKILL.md`: evidence-driven vertical slices, migrations, verification and review.

These files are reusable instructions for agents working in this checkout. They do not install hosted ChatGPT plugins or grant API permissions. The separately served catalog skill at `/.well-known/agent-skills/morea-catalog/SKILL.md` remains the store-operation contract.

## Working together

The user has requested sub-agent implementation work. Delegate independent tasks with explicit file ownership; keep shared routes, schema, CI and navigation under one integrator. Agents share the filesystem: do not switch branches, revert other work or commit another agent's unfinished files. Report changed paths, contracts, validation and remaining limitations to the integrator. Read applicable instructions before editing.

## Product and data boundaries

- Preserve tenant storefronts and checkout, the `fr/en/ar` public routes and Arabic RTL. Add operational tools under authenticated store admin unless a public API is explicitly needed.
- Respect the merchant's storefront setting. Disabled storefronts must not serve public localized shopping/checkout; admin, signed provider intake and authorized APIs remain available. Enabling later installs missing defaults without replacing existing content.
- Resolve records through the authorized store. Request IDs, hidden fields and a global record lookup do not establish tenant authorization. Platform-only sessions may have no current store.
- Extend existing order state, stock, money, Sendit and GraphQL/MCP contracts. Keep shipping state separate from confirmation attempts, call outcomes and accounting state.
- Use additive migrations with database constraints for identity/concurrency invariants. Do not enable live third-party sync simply to test a feature.
- Keep credentials, cookies, customer values and private API responses out of code, fixtures, logs and PRs. Use synthetic tenants and disconnected integrations for executable checks.

## Delivery

Build bounded features through service/model, authorized controller/API, usable admin UI and relevant verification. Follow `docs/implementation-workflow.md`. Existing smoke scripts require an isolated `RAILS_ENV=test` database; inspect each script before running it. Report checks actually run and distinguish code written, runtime verified and deployed behavior. A PR is reviewable work; merging may trigger production deployment through the existing Render integration.
