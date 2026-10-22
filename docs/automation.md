# Automation

CI runs security and style checks plus the existing catalog changeset/rollback and MCP inventory lifecycle smoke scripts against disposable PostgreSQL and Redis services. These smoke scripts write test data and must never run against production. The CI database is isolated; production credentials are not used.

Render deploys main through its existing GitHub integration. `render.yaml` declares `/up` as the health check; an existing service may need its Blueprint synced for this setting to apply. Configure Render's automatic deployment option to **After CI Checks Pass** if deployments should wait for all GitHub checks. A repository change alone cannot verify or change that private Render setting.

The Store operations workflow runs daily at 07:17 UTC or manually. It checks the public Render health endpoint and then queries the same store-scoped GraphQL API used by the Morea plugin for catalog issues, stock levels and order totals. Results appear in the Actions summary and a JSON artifact (14-day retention). Audit coverage is capped at 2,000 products. Reports contain aggregate data, without customer details. GitHub scheduled runs can be delayed and depend on Actions being enabled.

Set the repository Actions secret `MOREA_API_TOKEN` securely using the store's Admin → Settings → Agent API token. Do not paste it into chat or commit it. Optionally set Actions variable `MOREA_GRAPHQL_URL` to the selected store's HTTPS `/graphql` endpoint; default: `https://morea.ollazen.com/graphql`. Missing credentials cause the report job to fail visibly; public health checking runs first. The connected ChatGPT plugin's credentials are not available to GitHub Actions automatically.

Existing shipping automation remains in `SenditPollJob` and `config/schedule.yml`. The current free Render web service runs Sidekiq alongside Puma and can sleep, so in-process cron is not an always-on guarantee. For continuous processing, provision a dedicated worker or external Render cron after reviewing its cost and configure `SENDIT_EXTERNAL_CRON` consistently. This change does not provision paid infrastructure.

The Morea backend already supports audit, preview, apply, verification and rollback. The currently connected plugin exposes only a subset of those backend tools. Refresh the plugin's discovered tools to expose newly deployed capabilities. Scheduled reports do not generate product claims or change prices, inventory, orders or catalog content. Content automation should use preview/apply/verify with the store profile and its approval levels.
