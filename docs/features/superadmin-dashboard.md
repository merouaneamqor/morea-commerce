# Superadmin overview

`/superadmin` is the platform overview on the apex and known tenant hosts, including unpublished workspaces. It requires an active super-admin session; merchant accounts cannot access platform data. Sign in through `/admin/login`.

The overview links to existing workspace creation, billing, user management, access-request review and feature flags. Workspace entry uses the existing authorized POST action. The newest-workspace list and overdue-invoice queue each show at most 10 records.

Metrics are platform-wide:

- Workspaces: all workspaces, with a separate published-storefront count.
- Active users: active accounts, including platform staff.
- Orders today and in 30 days: all order statuses, using Casablanca calendar dates; 30 days includes today and the preceding 29 days.
- Paid this month: paid subscription invoices whose payment timestamp is in the current Casablanca month.
- Outstanding: issued subscription invoices, including overdue invoices.
- Overdue: issued invoices with a due date before today in Casablanca.

Subscription amounts are MAD and retain cents. They do not include merchant sales, COD collections, draft invoices or void invoices. These are database aggregates, not live provider checks. Reading the dashboard does not change billing state or contact providers.

Verification: `RAILS_ENV=test bundle exec rspec spec/requests/superadmin_dashboard_spec.rb` against a dedicated empty test database. Existing feature-flag, platform-dashboard and workspace-access request specs cover related navigation and permissions.
