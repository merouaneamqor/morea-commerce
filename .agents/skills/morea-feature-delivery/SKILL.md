---
name: morea-feature-delivery
description: Deliver a bounded Morea feature from evidence and existing code through migrations, UI, focused verification and a reviewable PR.
---

# Feature delivery

Use for implementing a new operational feature or coordinating independent implementation tasks. Start with the user goal, the existing Rails behavior and the feature's evidence; avoid rebuilding an established Morea capability.

## Evidence and scope

Cashod discovery is documented in [PR #90](https://github.com/merouaneamqor/morea-commerce/pull/90) and [tracker #33](https://github.com/merouaneamqor/morea-commerce/issues/33). Those artifacts may be on the planning branch rather than this checkout. Distinguish published features, frontend request references, successful read shapes and tested workflows. A GET returning 200 is not proof of mutation behavior, correct financial semantics or rendered UI parity. Browser screenshots, selected-record MCP reads, provider writes and several restricted modules remain separate validation work.

Define one vertical slice with a user-visible outcome, explicit tenant/actor boundary and acceptance scenarios. Record intentional Morea design choices rather than inventing unobserved Cashod behavior. Preserve public tenant shopping while extending store operations.

## Implement with clear ownership

Assign independent agents disjoint paths and migration timestamps. One integrator owns routes, `db/schema.rb`, shared models/layouts and CI. Communicate service inputs/results, route helpers and authorization requirements before integration. Do not change branches or commit shared unfinished work from a child task.

Prefer existing Rails services, Hotwire forms and admin components. Add the model/service invariants first, then tenant-scoped controller/API and usable interface. Include validation/error/empty states, bounded listing and relevant localization/accessibility behavior. Do not add implementation details to customer-facing copy.

Add migrations without rewriting historical migrations. Use unique indexes and foreign keys for durable identity rules, and transactions for related order/stock/audit changes. Explain rollback or data-backfill limits. Keep schema generation under the integrator's control after all migrations are present.

## Verify proportionately

Run the smallest meaningful checks for changed behavior, then required existing regressions affected by the change. Repository CI uses PostgreSQL, Redis, `RAILS_ENV=test`, Rails autoloading, security/lint checks and smoke scripts listed in `.github/workflows/ci.yml`. Existing scripts create data; inspect their environment guards and use disposable databases with synthetic credentials. Do not run test migrations or smoke scripts against production.

Check tenant denial, replay/concurrency and lifecycle invariants for business-state changes. For views, verify routes and rendered forms, including CSRF and rejection paths. Report unavailable tooling or failed checks precisely; syntax checks do not substitute for database/controller tests.

## Deliver and track

Describe the concrete resulting behavior, how it extends Morea, validation actually completed and material limits. Link implementation issues/epics and evidence. Keep planning acceptance distinct from shipped feature acceptance. Publish a reviewable branch/PR; merging to main can deploy through Render, so report deployment separately from code readiness. Do not close feature work as implemented when only the specification is complete.
