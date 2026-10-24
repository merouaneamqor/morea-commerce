# Tenant confirmation queue

`/admin/confirmations` is an operational screen; public tenant storefronts and checkout keep their existing routes and behavior. Available orders are active `new` orders with no carrier parcel. The queue is bounded to 50 rows per page; due callbacks precede fresh orders. Available, My claims and All new orders filters separate ready work from assigned or scheduled work.

Claim/release/outcome requests require an authenticated store admin (or platform super admin in a store context). The service locks the tenant-scoped order before creating its unique confirmation record, so simultaneous claims select one owner. Recording an outcome requires that owner. Notes are internal and capped at 2,000 characters. A callback requires a future time in the application timezone; it cannot be claimed until due. Outcomes and history are independent of shipping state.

Confirmed/cancelled outcomes use the existing order transition and inventory code in the same transaction as the confirmation attempt. Failures retain the claim and roll back the attempt, stock and disposition. Confirmation uses `sync_delivery: false`: it reserves inventory without creating a carrier parcel or sending a Sendit job. The existing OrderStatusJob still records the change (its current implementation only logs). All previous transition callers retain their existing auto-delivery behavior by default. Shipping from the order desk remains an explicit follow-up step.

This slice does not install a call provider, dial customers, pay commissions, auto-confirm, dispatch parcels or introduce new staff roles. Stale claims can be released by their owner; administrative reassignment/expiry is a later feature. Existing admin pages remain English; the new queue labels include EN/FR/AR and inherit the existing RTL layout. Service validation messages currently use English, matching existing admin validation conventions.

Verify only in an isolated test database:

```
RAILS_ENV=test bin/rails runner script/confirmation_queue_smoke.rb
```

The smoke covers tenant denial, competing claims, callbacks, claim ownership, retained attempts, stock reservation and insufficient-stock rollback, no carrier-dispatch job, bounded admin rendering and foreign-tenant visibility. It creates and deletes synthetic stores and never uses production contacts.
