---
name: morea-tenant-commerce
description: Preserve Morea's tenant storefront, public shopping flows, localization and authorization while adding commerce or operations features.
---

# Tenant commerce

Use for host routing, staff access, storefront, cart, checkout or store-scoped APIs. Inspect `app/controllers/application_controller.rb`, `app/models/store.rb`, `config/routes.rb` and the affected controller/service first.

## Keep the shopping surface

`Store.find_by_host` selects subdomain tenants; `Current.store` supplies controller context. The apex hosts platform administration, not a new storefront. Preserve current host behavior, existing customer URLs and the localized `/:locale` public routes. Each tenant keeps its homepage, collections, products, pages, cart, COD checkout and order tracking. Operational tables belong in admin; public commerce retains its existing merchandising design.

`ApplicationController` selects FR/EN/AR and provides `rtl?`; public locale selection and admin URL generation differ. Check French, English and Arabic flows when a change touches shared layouts or public navigation. Preserve variant availability, images and purchase interactions; existing verification includes `script/luxury_merchandising_smoke.rb` and `script/variant_picker_smoke.mjs`.

## Authorize every entry point

- Resolve admin records through `current_store` and require authenticated staff. `Admin::BaseController` authenticates admin access; a platform-only super admin may have no tenant, so tenant features need a store context before querying.
- Verify related orders, products, variants, customers and assigned users belong to that same store. Model/service entry points must enforce this too, because jobs and APIs bypass controllers.
- GraphQL and MCP select `current_api_store`; use that authorized context. A submitted `store_id` must never replace token ownership. OAuth callbacks and API keys must preserve their existing tenant scope.
- Inspect `Current` handling in asynchronous code; pass explicit store identity and re-scope loaded records. Avoid unbounded cross-store queries and data-bearing logs.

## Verify the boundary

Use two synthetic stores, separate staff and overlapping record identifiers where relevant. Test ordinary access, a foreign ID, an unauthenticated request and a platform-only session. For routing changes, also check apex, valid tenant and unknown host behavior. Ensure shared-layout changes do not remove public catalog/cart/checkout navigation. Use the isolated test setup in `.github/workflows/ci.yml`; never use live customer data as fixtures.

Keep tenant platform billing distinct from merchant sales. Existing past-due billing shows an admin warning while keeping the public storefront online; preserve that policy unless the requested feature explicitly changes it.
