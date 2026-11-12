# Unified Super Admin console

Platform staff use `/admin/platform` as the Seallo Super Admin console. Existing `/superadmin` ActiveAdmin pages and `/admin/platform*` URLs still resolve.

## Navigation

The platform shell covers overview, workspaces, access requests, staff, subscription billing, integrations, feature flags, operations, audit, privacy rights, and the platform agent API. Global search matches workspace name, slug, email, or connected shop domain.

## Overview

The overview is an action queue for overdue subscription invoices, pending access requests, integration failures, and open platform privacy requests. Each row opens the record that needs action. Workspace metrics and the workspace list remain below the queue.

## Workspace record

`/admin/tenants/:id` is the workspace operations page: identity, plan, staff, storefront, connections, and entry into merchant admin. Billing edit and reset stay on the existing edit page. Entering a workspace keeps a platform session marker so the workspace stays visible until return.

## Privileged writes

Sensitive actions (impersonation, invoice issue/pay/void, staff lifecycle, feature flags, workspace reset, integration recheck, privacy resolve) require confirmation where the UI mutates state and append `AuditEvent` rows through `Platform::AdminAudit`. Audit events never store tokens or buyer payloads.

## Billing

`/admin/platform/billing` lists cross-workspace subscription invoices and renewals in MAD. Recording payment accepts an optional payment reference and activates the workspace subscription. Merchant sales are not mixed into these totals.

## Verification

Use a disposable test database:

```bash
DATABASE_URL=postgres://maison:maison@localhost:5432/maison_test RAILS_ENV=test \
  bundle exec rspec \
  spec/requests/platform_dashboard_spec.rb \
  spec/requests/platform_search_spec.rb \
  spec/requests/platform_workspace_access_spec.rb \
  spec/requests/platform_billing_spec.rb \
  spec/requests/platform_integrations_spec.rb \
  spec/requests/platform_features_console_spec.rb \
  spec/requests/platform_operations_spec.rb \
  spec/requests/platform_audit_events_spec.rb
```
