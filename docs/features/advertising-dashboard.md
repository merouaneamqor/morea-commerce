# Advertising reporting

Authenticated tenant admin at `/admin/advertising`. Accounts, campaigns and daily MAD totals are entered manually; no provider credentials or live synchronization are configured. Reporting active/paused controls never change advertising delivery. Historical totals always include paused accounts and campaigns.

Each campaign/day has one replaceable record, protected by a unique database index. Load the campaign/day first to inspect and edit its current totals. MAD decimal amounts convert exactly to integer cents; negative amounts, fractional cents and non-integer counts are rejected. Date filters span at most 366 days.

Confirmed/delivered order counts and delivered revenue are reported figures, not order attribution. ROAS is delivered revenue divided by advertising spend (undefined with zero spend). Contribution subtracts reported product/delivery costs and advertising spend from reported delivered revenue. It excludes unreported costs and does not represent accounting profit. The dashboard deliberately offers no fictitious product attribution or automated advertising rules.

All account/campaign lookups are scoped to the authenticated workspace, including edit loads and status writes. Migration is additive; rolling it down deletes the new reporting history. No existing orders are changed or backfilled.

Verification: `RAILS_ENV=test bundle exec rspec spec/requests/advertising_dashboard_spec.rb` with an isolated PostgreSQL test database.
