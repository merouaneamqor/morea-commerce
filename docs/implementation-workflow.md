# Implementing Morea operations features

Morea supports both published storefronts and external-only merchant workspaces. Existing tenants retain their localized storefront, catalog, cart and COD checkout; new merchants may choose order operations without publishing a storefront. The `storefront_enabled` setting controls public shopping, while authenticated admin and signed order intake remain available. New back-office features extend its Rails admin and services. Provider contracts and current limitations are documented in `docs/features/connected-store-contracts.md`.

## Reusable project skills

`AGENTS.md` points agents to three local instruction packages:

| Skill | Apply when |
|---|---|
| `.agents/skills/morea-tenant-commerce/SKILL.md` | Changing host routing, tenant access, public shopping, localization or store-scoped APIs |
| `.agents/skills/morea-cod-operations/SKILL.md` | Changing intake, confirmation, stock, shipments, money or replay behavior |
| `.agents/skills/morea-feature-delivery/SKILL.md` | Turning evidence into an implemented, tested vertical slice or coordinating agents |

They are versioned repository instructions that agents can load in this checkout. They are not globally installed ChatGPT plugins, server tool registrations or new permissions. The existing HTTP-served catalog skill and connected MCP/GraphQL contracts remain separate.

## One feature cycle

1. Read the existing implementation and relevant skill. Choose a user-visible outcome and document its actor/store boundary, failure behavior and acceptance scenarios.
2. Use the [Cashod evidence PR](https://github.com/merouaneamqor/morea-commerce/pull/90) as reference, distinguishing observed reads from unverified writes and UI behavior. Preserve Morea's working capabilities.
3. Give agents disjoint file ownership. The integrator owns shared routes, schema, navigation, CI and final commits. Child agents report contracts and tests without switching branches or committing shared work.
4. Implement service/model, database constraints, authorized entry point and usable admin UI. Keep side effects idempotent and public storefront routes intact.
5. Migrate and verify against disposable test PostgreSQL/Redis. Run relevant smoke scripts and required CI checks; use disconnected providers and synthetic data.
6. Open a PR describing resulting behavior, evidence, checks and remaining limits. Link the parent epic and implementation issue. Code review, merge and production rollout are separate milestones.

For these first features, inspect `Orders::Editor` side effects and `Order` stock/state rules. Test two tenants, invalid related records, concurrent or repeated intake/claims, transaction rollback and stock changes. Preserve Sendit's ownership of delivery states. Never use real orders, customer messages, dispatch or paid providers as test fixtures.
