# Render memory investigation, 18 November 2026

## Production evidence

Read-only Render inspection in the confirmed workspace matched this repository to `morea-web`, service `srv-dbo858nf3r2c73aeei50`. No service named exactly `morea` was returned. The instance ID matches the reported failure.

- Live deploy `dep-dbu52e3rjlhs73bcq03g` runs `1e19b2619cbee7264bdf4d0d36028b58d51df298`, live since 17 November 13:09 UTC. Git ancestry confirms it includes `fe9f8bf`.
- The service is a single free Ruby web instance, starts `bin/render-start.sh`, and automatically deploys main. Preview generation is off. No configuration was changed.
- Event `evt-dbus6l6417fc73e0gpt0` confirms an OOM kill on `tt74d` at 15:25:08.211 UTC with a 512 MiB limit. Available again at 15:26:42.922 UTC.
- One-minute memory samples show 510.68 MiB at 14:30, 511.81 MiB at 15:25, against 512 MiB. After restart, samples reach 464.17 MiB at 15:27 and 492.14 MiB at 15:35. Metrics are instance/container totals, not per-process RSS or heap measurements.
- Longer samples show growth from about 404 MiB at 23:30 on 17 November to approximately 511 MiB by 08:00 on 18 November, with some intervening declines. The previous instance also grew toward the limit. This supports sustained working-set pressure and growth over time. It does not prove a live-object leak, allocator fragmentation, or a specific allocation spike.
- Final complete log window, 15:24:00 to 15:26:50 UTC: AssignmentRulesJob completed at 15:24:17 in 7.49 ms. DiscordOrderNotifyJob failed at 15:24:42 with URI::Generic/request_uri, after repeated retries. GET /admin/orders started 15:25:05.726 and completed 200 at 15:25:06.521, 44 SQL queries. The OOM followed about 1.69 seconds later. Temporal proximity does not establish causation.
- Restart logs confirm Puma single mode, three threads, Ruby 3.3.12 and Sidekiq's default pool size one. Both application processes booted. The script's seed/cleanup runner finishes before they start. Startup cleared 12 orphan jobs. A missing-class RotateBusinessRankingsJob retry was observed earlier. Shared queue contamination is a separate operational concern.

The connector has no read-environment operation, and get_service does not return environment variables. Actual MALLOC_ARENA_MAX, RUBY_YJIT_ENABLE, RUBYOPT, RAILS_ENV, WEB_CONCURRENCY and SIDEKIQ_CONCURRENCY values were not directly verified. Code defaults are not evidence of effective values. Puma's reported environment was `deployment`; Sidekiq reported Rails production. Startup logs also warned SMTP_ADDRESS is unset. No secret values are included here.

## Repository risks

All six reported risks are present in the deployed source and remain hypotheses for this crash.

| Code | Allocation risk and behavior constraint |
| --- | --- |
| Orders::ProductSearch | Ruby select loaded every visible active product and variant before first(25). Preserve locale folding, name/id order and active variant matching. |
| AccountingStats#inventory | Full tenant catalog and variants materialized. A later change can batch and count locally; preserve all statuses and inactive variant stock semantics. |
| Confirmations::AssignmentRunner | Entire unassigned and late queues loaded. Runs every minute, but returns early for no active rules. Batch in existing timestamp/id order to preserve fairness. |
| Orders::ShipmentReview | All candidates and phone-related history within 365 days loaded with items. Dispatch filters selected IDs only afterward. Arbitrary limits could miss duplicate parcels or cancellation warnings. This was not called by the last logged index action. |
| Connections::ProductSources | HTTP body buffered before the 8 MB check. Enforce incrementally while streaming, preserving pagination headers and error behavior. |
| MediaWarmupJob | Image GET buffered although only status is needed. Stream/discard while preserving GET transformations and 423 retries. |

## Change and limits

The feature branch bounds product search to 100 products plus their variants per scan batch, stops at 25 matches, and disables query caching during scanning so earlier raw query results are not retained. Empty queries keep their existing 10-result database limit. Tenant/visibility/status scopes, name/id order and Unicode/locale matching remain intact. No SQL approximation of accent matching was introduced.

This reduces a confirmed allocation risk. It is not a demonstrated fix for the production OOM. Scans without matches still examine the catalog, OFFSET costs increase for later batches, one product can still have many variants, and concurrent catalog edits can shift offset pages. This does not establish a fixed byte budget.

## Remaining production checks

1. Inspect only the allowlisted non-secret effective settings in both running processes: WEB_CONCURRENCY, SIDEKIQ_CONCURRENCY, RAILS_MAX_THREADS, RUBY_YJIT_ENABLE, MALLOC_ARENA_MAX, RAILS_ENV and whether RUBYOPT enables YJIT. Check RubyVM::YJIT.enabled? in the actual application processes. Do not dump the environment. Check SOLID_QUEUE_IN_PUMA presence because the Puma config treats any value as enabled.
2. Capture process-level RSS/PSS and Ruby GC heap/live-object statistics for Puma and Sidekiq from cold boot through representative requests and scheduled jobs. Pair with container memory.current and memory.stat to separate heap, native allocations and filesystem cache. Existing metrics cannot identify the responsible process.
3. Correlate request/job durations with higher-resolution memory samples, including orders index, product picker, accounting inventory, assignment backlog, shipment review, imports and image warmup. Use synthetic tenants in staging; record counts rather than customer data.
4. Compare retained live objects after GC across repeated workloads to distinguish a leak from an allocation high-water mark. Measure idle fully booted memory before deciding whether the combined baseline fits 512 MiB.
5. Inspect shared Redis queue ownership and the missing-class retries without deleting jobs or disabling workers. Diagnose the Discord URI configuration separately without exposing its webhook.
6. After review and explicit deployment authorization, measure the same workloads on the approved commit. No merge, deploy, paid-plan change or background-processing shutdown was performed.

## Validation

Executed in a disposable Ruby 3.3.12 container with application gems and a dedicated PostgreSQL `morea_test` database, using synthetic local credentials and the test job adapter:

- `ruby -c` on the service and new spec: both pass.
- `bundle exec rspec spec/services/product_search_spec.rb`: 4 examples, 0 failures, seed 34165.
- `bundle exec rspec spec/requests/orders_flow_spec.rb spec/requests/product_sources_spec.rb spec/requests/agent_space_spec.rb`: 42 examples, 0 failures, seed 5864.
- RuboCop for the changed service and spec: 2 files, no offenses.
- Test Tailwind and Dart Sass asset builds, `bin/rails zeitwerk:check`, and `git diff --check`: pass.

The full suite, security scans, remaining CI smoke/browser checks, production load/memory measurements and post-deployment validation were not run. Initial setup failures were resolved by installing missing dependencies and the workspace's trusted CA certificates in the disposable container; certificate verification remained enabled. No production database, Redis or external provider was used by these tests.
