# Morea storefront performance audit

The suite drives the Rails HTML flow using one cookie jar per k6 iteration. It follows only validated same-origin locations, reads forms for IDs and CSRF tokens, and does not load browser assets or execute scripts. Browse profiles cover the redirect, homepage, collections, collection detail and a product with a variant. The separate checkout profile adds the variant, reads the resulting cart, updates quantity, opens checkout, submits a fictional COD order, and verifies the receipt and quantity. PostgreSQL regressions cover duplicate checkout, stock races, and tenant authorization separately.

| Profile | VU ceiling | Peak journeys/s | Peak hold | Mode |
|---|---:|---:|---:|---|
| Smoke | 1 | 1 | 10s | Browse |
| Baseline | 20 | 3 | 60s | Browse |
| Moderate | 50 | 8 | 90s | Browse |
| High | 100 | 15 | 90s | Browse |
| Stress | 250 | 30 | 90s | Browse |
| Extreme | 500 | 60 | 90s | Browse |
| Spike | 200 | 30 | 20s | Browse, 2s ramp from zero |
| Checkout | 5 | 1 | 15s | Synthetic COD |

VU ceilings are not achieved concurrency. k6 uses an [open arrival model](https://grafana.com/docs/k6/latest/using-k6/scenarios/executors/ramping-arrival-rate/) so slower responses do not silently reduce offered load. Five HTTP requests per completed browse journey bound extreme traffic at about 300 requests/s. Requests time out after 4s; scenarios have a 15s grace period. Thresholds fail at 1% HTTP errors, 1% incomplete journeys, any dropped iteration, or read endpoint p95 at or above 500ms. Severe error or journey failure rates (10%) abort after a 5s evaluation grace period. Monitor infrastructure separately and interrupt on saturation.

### Disposable local run

From the repository root on Linux/macOS or Git Bash with Docker:

```bash
docker build -f Dockerfile.dev -t morea-web:latest .
docker build -f performance/Dockerfile -t morea-performance-local:locked .
export PERF_TARGET_TOKEN="$(openssl rand -hex 24)"
mkdir -p performance/results
docker compose -f performance/compose.yml up -d --wait web
docker compose -f performance/compose.yml run --rm k6 run --summary-export results/smoke.json k6/smoke.js
docker compose -f performance/compose.yml run --rm k6 run --summary-export results/baseline.json k6/baseline.js
ALLOW_SYNTHETIC_ORDERS=yes docker compose -f performance/compose.yml run --rm k6 run --summary-export results/checkout.json k6/checkout.js
docker compose -f performance/compose.yml exec -T web env -u PERF_TARGET_TOKEN bundle exec rails runner script/storefront_regression.rb
docker compose -f performance/compose.yml down
```

Compose uses fresh PostgreSQL in tmpfs and an internal network with no published ports; k6 shares only the web network namespace. It forces the Rails test adapter and enables real CSRF checking for the k6 run. The Rails regression runner uses the repository's test convention and runs in CI against PostgreSQL. Use a fresh stack per comparison; web startup loads the schema and seeding requires an empty store table. Test framework, null cache and fixture size make this a correctness harness and local comparative baseline.

### Isolated staging run

Configure only a disposable Rails test instance with the fixture, `PERF_TARGET_TOKEN`, and optionally `PERF_SYNTHETIC_ORDERS=yes`. Block outbound traffic, disable integrations, and use a fresh database and separate secrets. Approve the exact HTTPS origin and set:

```bash
export TARGET_ENV=staging BASE_URL=https://audit.example.test
export APPROVED_STAGING_ORIGIN="$BASE_URL" ISOLATION_CONFIRMED=yes
export PERF_TARGET_TOKEN=... # same token on the isolated app and runner
bash performance/scripts/run-tests.sh smoke
bash performance/scripts/run-tests.sh baseline
BASELINE_PASSED=yes bash performance/scripts/run-tests.sh moderate
# Advance one profile at a time only after reviewing app and infrastructure metrics.
ALLOW_SYNTHETIC_ORDERS=yes bash performance/scripts/run-tests.sh checkout
```

Remote runs require a matching token and application preflight; known production origins are denied. Keep the token out of shell logs. The entry scripts reject redirects by default. For CI, use the same local sequence and archive `performance/results/*.json`. Retain the machine, image, fixture counts, configuration, run window, and deployed revision with each result. Sample CPU, memory, database activity and connection waits, Redis latency, and Sidekiq queue age over the same interval.
