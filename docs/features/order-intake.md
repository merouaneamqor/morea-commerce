# Tenant-scoped external order intake

`Orders::Intake` is the first internal connector boundary. It leaves public tenant storefronts, checkout and all existing API routes in place. No external merchant account is connected or synchronized by this change. The API controller supplies the token-authorized store; callers cannot select a store in the payload. POST `/api/v1/order_imports` accepts `{ source, external_id, order: attrs }` with the existing store/OAuth bearer token and returns only order ID/number/status and created/replayed flags (201 on creation, 200 on replay).

```ruby
result = Orders::Intake.new(store: authorized_store, user: current_user).call(
  source: "shopify",
  external_id: "order-77",
  attrs: {
    name: "Customer", phone: "0612345678", city: "Casablanca", address: "Address",
    lines: [{ product_id: authorized_store.products.first.id, quantity: 1 }],
    shipping_dh: "20.00"
  }
)
result.order
result.created? # false on a repeated tenant/source/external_id
result.replayed?
```

Resolve the tenant and authenticate/authorize the caller before calling the service. The parent integration exposes this boundary through the existing store-token authentication; this service does not define a new credential scheme. A supplied staff user must belong to that store, unless a super admin. Trusted background callers may omit the user.

The unique database identity is `(store_id, source, external_id)`. Source is normalized to lowercase and limited to 64 letters/digits/underscore/hyphen characters. External IDs are nonempty printable strings up to 255 characters. Retries return the original order without applying changed payloads, recalculating prices or adding customer/address/event records. A source ID is not an authorization token. Only connector identity is stored; full inbound payloads and secrets are not retained.

A tenant row lock serializes imports, including concurrent duplicates. Customer/address, order/items, source identity and import event commit atomically. The database unique index protects identity uniqueness even for code outside this service. This first implementation favors correctness over per-tenant import throughput; replace serialization only with equivalent transaction and concurrency tests.

`Orders::Editor` remains the pricing/contact creation authority. Intake checks active tenant-owned catalog products, active selected variants, text contact fields, simple text tags, integer quantities and nonnegative two-decimal shipping/discount values before invoking it. Shipping and discount inputs are bounded at 2,147,483,647 cents using decimal arithmetic before conversion, matching the current signed SQL integer money columns and preventing overflow/Infinity errors. Variant products require a variant. Payloads cannot override store, currency, order status or catalog line prices. The new order is COD in `new` state, with no stock reservation until the existing confirmation transition runs.

`Orders::Editor.new(external_effects: false)` suppresses Sendit destination lookup and the status/Discord creation notifications for intake. The default is `true`, preserving current staff/admin create behavior. No Sendit dispatch/sync is performed. Connectors must add explicitly reviewed post-commit integrations or an outbox later; intake does not enqueue them implicitly. Existing staff-created event text is retained for Editor compatibility and an additional source-provenance `comment` event distinguishes source provenance.

Validation errors raise `Orders::Intake::Error`. Infrastructure/database errors that are not validation errors propagate, so a future connector can retry rather than acknowledge an unpersisted order. Replay does not require a valid changed payload: the original stored order remains authoritative.

Run `RAILS_ENV=test bin/rails runner script/order_intake_smoke.rb` only against an isolated test database. It covers duplicate and concurrent replay, tenant/source separation, invalid payloads, transaction rollback, variant requirements and no stock/notification side effects. Provider webhooks/signatures, field mapping, price overrides, actual sync, public API keys and order-change reconciliation remain separate work.
