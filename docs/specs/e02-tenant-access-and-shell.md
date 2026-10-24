# E02 — Tenant access, roles and operational shell

Epic #35 · work packages #51, #52, #53 · project #33 · depends on #34 (E01).

**Status: specification only.** Evidence labels used below:

- **code** — read in this checkout, not exercised against a deployment.
- **published** — Cashod public claims (`docs/cashod/gap-matrix.md`, features F196/F197/F209 in the discovery evidence, PR #90). No authenticated workflow has been verified.
- **proposed** — Morea design; needs review before implementation.

Nothing here claims Cashod parity. Cashod role names, permission granularity, 2FA flow and store-switcher behavior are **unverified** until E01 delivers authenticated evidence.

## 1. Current Morea baseline (code)

| Area | What exists | Source |
|---|---|---|
| Identity | `User` belongs to at most one store; platform-only super admins have no store. Email unique per store, globally unique for platform-only super admins. | `app/models/user.rb` |
| Roles | Two booleans: `admin` (default true) and `super_admin`. `require_admin!` admits either. There is no non-admin staff access: a user with `admin: false` is redirected to login. The staff list labels these "Staff", but they cannot sign in to the admin. | `app/controllers/admin/base_controller.rb`, `db/schema.rb` |
| Tenant resolution | Staff resolve via the host's store; super admins resolve from any host. | `ApplicationController#current_admin_user` |
| Store switching | Super admin only: `tenants#enter` sets `session[:admin_mode] = "store"` and redirects to the store origin. Store staff cannot belong to several stores. | `app/controllers/admin/tenants_controller.rb` |
| Session | Rails cookie store (`_morea_session`), `session[:user_id]`. No `expire_after`, no server-side session record, and no `reset_session` on login or logout found in `app/`. | `config/initializers/session_store.rb`, `sessions_controller.rb` |
| 2FA / throttling | No TOTP/OTP or login throttling found in `Gemfile`, `config` or `app`. | grep |
| API tokens | Store API token stored as SHA-256 digest; OAuth tokens stored as digests with `expires_at`, scoped by `store_id`. | `app/models/store.rb`, `oauth_access_tokens` |
| Audit | `order_events.user_id` (nullify on user delete, no source). `confirmation_attempts` keeps `actor_label` so history survives staff deletion. No general audit log; no event for staff, role, session or token changes. | `db/schema.rb` |
| Admin layout | Single `admin` layout plus `admin_platform`; navigation is a flat list. | `app/views/layouts/` |

## 2. #51 — Operator roles and store switching

### Gaps
1. No permission model between "can use admin" and "cannot". Call-center agents, warehouse staff and accountants (needed by E04, E07, E10) would otherwise all get full admin.
2. One user ↔ one store. An operator running two stores needs two accounts and two passwords.
3. `admin` defaults to true and "Staff" is a dead state.

### Proposed design
- **`memberships`** table: `user_id`, `store_id`, `role`, `status`, timestamps; unique `(user_id, store_id)`. `users.store_id` stays during transition and is backfilled into a membership with role `owner`.
- **Roles** (proposed, closed set first): `owner`, `manager`, `agent` (confirmation queue and orders), `warehouse` (inventory, returns), `finance` (read orders and money). Role → permission mapping lives in one Ruby table (`Permissions`), not in views.
- **Deny by default:** every admin controller declares the permission it needs; a missing declaration fails closed in test (a CI check enumerates `Admin::*Controller` actions).
- **Store switcher:** lists the user's active memberships; switching redirects to that store's origin (cookies are host-scoped on localhost, shared on `*.lvh.me`), then re-resolves the membership server-side. A request id or hidden field never selects the store.
- **Platform admin** stays a separate concept (`super_admin`), and acting in a store is recorded as such in audit (see #53).
- Last-owner protection replaces today's "keep at least one admin" check, per store.

### Acceptance scenarios (synthetic data only)
| # | Scenario | Expected |
|---|---|---|
| R1 | `agent` in store A opens `/admin/orders`, confirmation queue | allowed |
| R2 | `agent` opens `/admin/staff`, `/admin/store`, `/admin/agent_api` | 403/redirect, no data in body |
| R3 | Member of A and B switches to B | only B's records appear; session shows B |
| R4 | Member of A requests an order id from B (UI, GraphQL, MCP, queue claim) | 404, no existence leak |
| R5 | Membership of B suspended mid-session | next request to B denied |
| R6 | Demote or delete the only `owner` | rejected |
| R7 | Background job enqueued for store A runs after the user lost access | job acts on store A data; actor recorded as stored label, not re-authorized as the user |
| R8 | Existing staff after migration | one `owner` membership each; login unchanged |

### Open questions (need E01 evidence)
Cashod role names and per-module permissions; whether one login spans stores; whether agents see order totals and customer phone numbers; commission visibility.

## 3. #52 — Dense, responsive operations navigation

### Gaps
Flat admin nav will not scale across E03–E14 modules; no saved filters; table density and keyboard handling are per-view.

### Proposed design
- **Grouped navigation** by job, not module count: *Sell* (orders, confirmation, customers), *Fulfil* (inventory, shipments, returns), *Money* (reconciliation, invoices), *Grow* (products, collections, pages, pixels), *Settings* (store, staff, API). Groups and items are filtered by the role's permissions (#51); empty groups are hidden.
- **Responsive:** collapsible sidebar ≥ md; bottom sheet or drawer below md. Tables degrade to stacked rows with the primary action preserved.
- **RTL:** logical CSS properties (`ms-*`/`me-*`, `text-start`) so Arabic mirrors without a separate stylesheet; verified with `dir="rtl"` snapshots for each shell page.
- **Keyboard:** skip link, visible focus, `g`-prefix navigation shortcuts that do not fire inside inputs, arrow-key row navigation in the order and queue tables.
- **Saved filters:** per `(membership, page)` named filters in a small `saved_filters` table (JSON params whitelisted per page). Never shared across stores.
- **Accessible errors:** `aria-live` flash region, field errors linked via `aria-describedby`, error summary focused after a failed submit.
- The public storefront layouts are untouched.

### Acceptance scenarios
| # | Scenario | Expected |
|---|---|---|
| N1 | `agent` role loads admin | Only permitted groups render |
| N2 | 360 px viewport | No horizontal page scroll; primary actions reachable |
| N3 | Arabic locale | `dir="rtl"`; nav, tables and forms mirrored |
| N4 | Keyboard only | Reach every nav item and submit a form without a pointer |
| N5 | Failed form submit | Focus moves to error summary; each field error announced |
| N6 | Saved filter in store A | Not listed after switching to store B |

## 4. #53 — Session hardening and actor audit

### Gaps (code)
1. Sessions never expire and cannot be revoked server-side; changing a password does not end other sessions.
2. Login does not rotate the session identifier (`reset_session` not found); no login throttling.
3. No 2FA.
4. Audit actor is only `user_id` on order events, nullified on deletion, without source (UI, API, MCP, job) or store.

### Proposed design
- **Server-side sessions:** `admin_sessions` (`user_id`, `store_id` or null, `token_digest`, `created_at`, `last_seen_at`, `expires_at`, `revoked_at`, `ip`, `user_agent`). Cookie carries only a random token; `current_admin_user` resolves through an unexpired, unrevoked row. Idle timeout and absolute lifetime configurable (initial proposal: 12 h idle / 30 d absolute — to be validated).
- **Rotation:** call `reset_session` on login and logout; revoke all other sessions on password change and on role/membership change.
- **Throttling:** per-email and per-IP attempt limits on login with uniform error text.
- **Optional TOTP 2FA** per user (enrol, confirm with a code, hashed recovery codes). Owners may require it per store. Platform admins should be required.
- **`audit_events`** (append-only): `store_id`, `actor_user_id`, `actor_label` (kept after user deletion), `source` (`ui|api|mcp|job|system`), `acting_as_platform` (boolean), `action`, `subject_type/id`, `metadata` (redacted), `created_at`. Written for sign-in/out, failed sign-in, password change, 2FA change, role/membership change, token create/revoke, session revoke, tenant entry by platform admin.
- **Token boundaries:** API/OAuth tokens already carry `store_id`; add tests that a token cannot read or write another store through REST, GraphQL or MCP, and that revoked/expired tokens fail.

### Acceptance scenarios
| # | Scenario | Expected |
|---|---|---|
| S1 | Session idle past timeout | Redirect to login, row unusable |
| S2 | Owner revokes another user's session | Next request from it is signed out |
| S3 | Password change | All other sessions revoked, current kept |
| S4 | Pre-login session id | Differs after login |
| S5 | Repeated bad passwords | Throttled; message identical for unknown email |
| S6 | 2FA enabled | Password alone does not open a session; recovery code works once |
| S7 | Store A token against store B ids | Denied via REST, GraphQL and MCP |
| S8 | Delete a staff user | Audit rows remain with `actor_label` |
| S9 | Platform admin enters a store | `audit_events` row with `acting_as_platform: true` |
| S10 | Audit rows contain secrets or customer phone values | Never (redaction test) |

### Open questions
Cashod 2FA method (TOTP, SMS, email) and session lifetime; whether they expose a login-history screen; legal retention for audit data in Morocco (CNDP) and French/EU customers.

## 5. Proposed implementation stories (not started)

Order matters: audit and sessions first because roles depend on trustworthy actor identity.

1. `audit_events` model, writer service, and wiring for existing staff/token actions.
2. Server-side sessions with rotation, expiry, revocation and login throttling.
3. `memberships` + `Permissions` + deny-by-default CI check, with backfill migration.
4. Store switcher and membership management UI.
5. Grouped, role-aware navigation shell with RTL/keyboard/accessibility checks.
6. Saved filters.
7. Optional TOTP 2FA.

Each story needs two-tenant tests, a rollback note for its additive migration, and a linked PR. Completing this document does not mean any of it is shipped.

## 6. Evidence still required

- Authenticated Cashod screens for role management, store switcher and security settings (E01 #48).
- Redacted observed traffic for login, session and role endpoints (E01 #49).
- Signed-off gap matrix row for "Tenants and users" (E01 #50).
