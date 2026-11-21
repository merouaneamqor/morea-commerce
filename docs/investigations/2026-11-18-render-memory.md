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

## Follow-up investigation and optimization

The second investigation exhausted the connected access paths available here. The connector has no process execution or environment-read operation, no Render API credential is available in the execution environment, and opening the dashboard with the browser failed with `the gaas-browser node_repl sandbox cannot be disabled`. No other browser session was accessed. The only connected PostgreSQL instance is named `test-db`; its relationship to this service could not be verified, so it was not queried. Key Value inventory matches the Redis resource seen in Morea's logs.

### More production correlation

The complete filtered request query for 14:30:00 through 15:25:08 UTC returned 57 `Processing by` lines without another page. It included 23 product-page requests, 13 vitals requests, 7 platform-home requests, 4 storefront-home requests, checkout/cart requests, one sitemap, one confirmation center, one pricing page, and the final orders index. There were no product-search, inventory-accounting or shipment-review request actions in that window. Those allocation risks cannot be assigned responsibility for the final memory growth from this evidence.

The 04:55 to 05:10 log window also showed ordinary routing misses, platform-home traffic, short assignment jobs, a missing-class `RotateBusinessRankingsJob` retry, and two MetaAdsSyncJob executions at 05:05. Memory samples were already approximately 504 MiB at 05:00; the largest step in that short interval preceded those Meta jobs. Neither the duplicate job nor its duration proves a memory cause. Queue ownership remains a production configuration check, not a reason to delete jobs during this investigation.

The connector's minimum metric resolution is 30 seconds. The last samples are 536,670,200 bytes at 15:24:30 and 536,674,300 bytes at 15:25:00. They cannot capture or attribute a subsecond allocation near the kill.

### Reproduced allocation behavior

Local production-mode Ruby 3.3.12 boots with YJIT disabled and MALLOC_ARENA_MAX=2 used roughly 209 to 218 MiB RSS per process after GC. This was a disposable container with synthetic local database settings, not the Render instance. RSS includes shared file mappings, so adding two RSS numbers is not a measurement of container usage. It nevertheless demonstrates the limited margin when loading Rails separately for Puma and Sidekiq.

A separate production-mode probe exercised 2,500 synthetic missing-route requests, then 500 pairs of empty AssignmentRulesJob/CloseStaleShiftsJob executions, all against the isolated local test database. Active Job used the test adapter and no provider calls were made. At 100 versus 2,500 missing routes, live slots stayed at 646,137 and measured live object bytes stayed approximately 70,991,630, while allocated heap pages rose from 881 to 1,115 and RSS rose from 224,380 to 249,208 KiB. This reproduces Ruby heap expansion and retained free capacity without corresponding live-object growth in that workload. It does not establish a production leak or account for all production traffic.

With RUBY_GC_HEAP_GROWTH_FACTOR=1.1, the same workload ended at 230,044 KiB RSS and 945 heap pages, compared with 254,852 KiB and 1,203 pages under the Ruby default. Post-boot probe elapsed times were 1.947 and 1.951 seconds respectively. This single small workload is not a throughput or production capacity guarantee. The startup script now supplies the overridable 1.1 default to its runner, worker and web processes. Existing explicit settings take precedence.

The inventory benchmark used 5,000 synthetic products and 50,000 variants, query caching enabled, separate fresh Rails processes, and RSS sampling every 5 ms. The original scan rose from 139,140 to 259,632 KiB; the optimized scan rose from 139,168 to 148,148 KiB. Both returned 10,000,000 cents, 5,000 products, zero out of stock and zero missing costs. Incremental sampled peak fell from 120,492 to 8,980 KiB, approximately 92.5%. These fixture sizes are not known production catalog sizes.

### Additional changes

- Inventory now scans batches of 100 with query caching disabled and maintains its product count locally. Drafts and inactive variant stock retain their existing accounting semantics.
- Automatic assignment uses timestamp/id keyset batches of 100. It captures the cursor before updating attribution timestamps, preserving chronological priority, fair distribution and timeout transfers while avoiding OFFSET skips as rows leave the queue.
- Shipment review calculates cancellation counts and latest dates in SQL. Only possible duplicate statuses in the relevant date range load line items. The original tenant boundary and 365-day cutoff remain. The existing response still retains all candidate rows and their items; it has not been silently capped.
- Product source HTTP reads reject excess bytes during streaming and preserve pagination headers and status classifications. Images are streamed and discarded by media warmup, retaining GET transformations and 423 retries.

No production state was changed. A high combined baseline plus retained allocation capacity is now a reproduced explanation for memory pressure, but the exact process and allocation that crossed Render's limit remain unconfirmed. A production process snapshot is required before calling that the crash's established root cause.

### Follow-up validation

The combined service/request run passed 146 examples with seed 8539. The same 146 examples also passed with the proposed heap growth factor, seed 10089. Changed-file RuboCop passed across 12 Ruby files; Rails autoloading, shell syntax, whitespace checks and two isolated startup-wrapper tests passed. The wrapper tests stub `bundle`, verify all three processes inherit the default, and verify explicit tuning is preserved. The full suite and full security/browser CI were not run.

The repeatable synthetic probe sources and outputs are workspace artifacts under `/workspace/scratch/`: `inventory_memory.rb`, `runtime_memory_probe.rb`, `runtime_memory_gcdefault_results.log` and `runtime_memory_gc11_results.log`. They are investigation fixtures, not production commands.

### Minimal live snapshot still needed

Run this from the existing Render Shell. It reads only process names, memory counters and selected non-secret configuration. It does not launch another Rails application, print command lines or dump the environment. A single sample distinguishes the larger process; samples taken idle and after a known workload help identify growth. Reading another process may be restricted on the platform.

```ruby
# Run with plain ruby, not rails runner.
require "json"
Dir["/proc/[0-9]*/status"].each do |path|
  begin
    status = File.read(path)
    next unless status[/^Name:\s+(.+)$/, 1].to_s.match?(/ruby|puma|sidekiq/)
    directory = File.dirname(path)
    command = File.binread("#{directory}/cmdline")
    role = command.include?("sidekiq") ? "sidekiq" : (command.include?("puma") ? "puma" : nil)
    next unless role
    env = File.binread("#{directory}/environ").split("\0").to_h { |entry| entry.split("=", 2) }
    settings = {}
    %w[WEB_CONCURRENCY SIDEKIQ_CONCURRENCY RAILS_MAX_THREADS MALLOC_ARENA_MAX RUBY_GC_HEAP_GROWTH_FACTOR].each do |key|
      value = env[key]
      settings[key] = value.nil? ? "unset" : (value.match?(/\A(?:\d+(?:\.\d+)?|auto)\z/) ? value : "other value set")
    end
    settings["RAILS_ENV"] = %w[production development test staging].include?(env["RAILS_ENV"]) ? env["RAILS_ENV"] : "unset or other"
    settings["RUBY_YJIT_ENABLE"] = %w[0 1 true false].include?(env["RUBY_YJIT_ENABLE"]) ? env["RUBY_YJIT_ENABLE"] : "unset or other"
    settings["RUBYOPT_enables_yjit"] = env.fetch("RUBYOPT", "").match?(/(?:\A|\s)--(?:enable-)?yjit(?:\s|=|\z)/)
    memory = %w[VmRSS RssAnon RssFile].to_h { |key| [key, status[/^#{key}:\s+(\d+)/, 1]&.to_i] }
    puts JSON.generate(pid: directory.split("/").last.to_i, role: role, memory_kib: memory, settings: settings)
  rescue Errno::EACCES, Errno::ENOENT
    next
  end
end
```

This reports YJIT settings, not RubyVM::YJIT.enabled? inside the target process. That runtime state and retained-heap attribution still require in-process instrumentation or a profiler. Do not infer them from a new rails runner process.
