# Codify specs

Run with `RAILS_ENV=test` against a dedicated PostgreSQL test database, such as `codify_specs_test`. The harness refuses other environments and database names without a separate `test` segment before schema preparation. Active Job uses the test adapter. Regular specs roll back synthetic records; the concurrency specs commit their own synthetic fixtures so worker connections can see them, then remove only those records.

```sh
RAILS_ENV=test DATABASE_URL=postgres://maison:maison@db:5432/codify_specs_test bin/rails db:prepare
RAILS_ENV=test DATABASE_URL=postgres://maison:maison@db:5432/codify_specs_test bundle exec rspec
```

These URLs are for the repository's disposable Docker PostgreSQL service. For a host-run process, use the test database on your local PostgreSQL port instead. Build stylesheets (`RAILS_ENV=test bin/rails tailwindcss:build`) first if rendered pages have no asset build yet. CI prepares PostgreSQL/assets and runs `bundle exec rspec` automatically.

- Request approval specs cover pending signup, separate access-request navigation, review without provisioning, both storefront preferences, validation rollback, rejection, stale submissions, authorization and FR/EN/AR.
- Concurrent decision specs use separate HTTP sessions and database connections to check simultaneous approvals and approval versus rejection. A request must have one terminal decision and at most one approved workspace.
- Dashboard request and service specs cover tenant boundaries, workspace modes, calendar periods, exact cents/separate currencies, source health, active work, provider setup links, inventory and localization.

No provider, carrier or customer messaging is used as a fixture. Run one spec file by passing its path, or replay a reported ordering seed with `bundle exec rspec --seed NUMBER`. Existing scripts under `script/*_smoke.rb` remain complementary integration coverage.
