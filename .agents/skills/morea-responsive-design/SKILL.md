---
name: morea-responsive-design
description: Implement and verify responsive Morea storefront, merchant admin, platform and authentication screens while preserving FR/EN/AR flows.
---

# Responsive Morea screens

Read AGENTS.md and the tenant-commerce and feature-delivery skills. Inspect the actual template and its layout before changing CSS. Public commerce uses `.storefront-body`, merchant/platform admin uses `.admin-body`, authentication uses `.seallo-auth`, and registration/subscriptions use `.seallo-flow`. Keep overrides within their surface; load each stylesheet through its existing layout. Preserve tenant authorization, forms, cart/checkout and locale routes.

Coordinate agents with disjoint ownership of public commerce, admin, platform/auth and automated tests. Tell the integrator which layout must load new assets. Send browser failures directly to the responsible agent with viewport, direction, selector and observed overflow. One integrator owns shared layout/navigation and CI changes.

Use intrinsic sizing: `min-width: 0` for grid/flex children, `minmax(0, 1fr)` tracks, bounded replaced elements and wrapping for merchant-provided text. Let controls and action groups wrap; keep primary actions reachable. Keep dense data tables readable inside local horizontal scrollers. Do not hide page overflow to conceal an oversized child. Preserve Arabic RTL with logical properties. Use 16px form text on phones and adequate touch targets. Consider short landscape screens, fixed bars, cookie notices and open dialogs together.

Run the commands and browser matrix in docs/responsive-validation.md. Test 320px phones, intermediate widths and desktop, both directions, long text and populated tables. Component fixtures exercise real CSS but do not prove controller rendering, navigation or submission. For live verification use an isolated test database, synthetic tenants and disconnected integrations, then pass an explicit route manifest and browser storage state. Check drawer open/close, focus, cart quantities, variant selection, checkout validation, and localized labels. Never use production cookies or customer data in committed artifacts.

Report the actual number of checks, their mode and remaining device/runtime limits. Save failures under ignored tmp; do not claim all pages or real iOS/Android verification from synthetic fixtures. Add newly discovered layout patterns to fixtures so subsequent changes catch the same regression.
