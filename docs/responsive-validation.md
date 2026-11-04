# Responsive verification

The application shares responsive CSS across the storefront, merchant/platform administration, public platform documents, authentication and subscription flows. The browser harness renders representative components with the actual compiled Tailwind and surface stylesheets, using long synthetic labels and populated tables.

## Reproducible component checks

```sh
npm ci
npx playwright install chromium
npm run build:test-css
npm run test:responsive
```

Set `CHROMIUM_PATH=/usr/bin/chromium` to use an existing system browser. Node 20+ is required. The script tests 320×640, 375×812, 768×1024, 1024×768, 1440×900 and 812×375 in LTR and RTL. It checks document width and visible element bounds, allowing intentional horizontal scrolling inside table/pre containers. It writes the check count and any failing selectors to ignored `tmp/responsive-results.json`.

The component matrix covers accounting cards and income rows, the date-picker template with calendars rendered by its actual JavaScript controller, admin layouts, member cards, wide tables, form controls, checkout fields and sticky actions, rich storefront content, storefront navigation, platform header actions, authentication language links and public document content, accounting cards/income rows and the shared date picker. The latest-source matrix contains 108 geometry checks; date-picker cases render the current partial and controller. It does not boot Rails, submit forms, authenticate users or prove that every route renders correctly. RTL geometry checks change direction; they do not translate fixture strings.

## Live route checks

Start Rails against an isolated test database with synthetic data and disconnected providers. Build normal Rails assets and serve them. Create a JSON array containing explicit absolute URLs for all routes and populated/empty states to verify; include separate French, English and Arabic URLs. Never point the harness at production.

```sh
RESPONSIVE_URLS=/tmp/responsive-urls.json \
RESPONSIVE_STORAGE_STATE=/tmp/synthetic-admin-state.json \
npm run test:responsive
```

Storage state is optional for public pages. Keep authentication state outside the repository. The harness rejects failed HTTP responses and redirects to a different path, so a sign-in page cannot silently count as an admin-page pass. Use separate manifests/states for tenant storefront, merchant admin and platform-only admin. Run each surface separately to preserve host and actor boundaries. Live mode uses each page's real stylesheets, while the fixture build remains a prerequisite.

In addition to the geometry audit, manually exercise mobile navigation, admin drawer keyboard dismissal, cookie notice, cart drawer and quantity controls, variant selection, purchase bars, checkout error states and successful synthetic checkout. Check tall dialogs and short landscape screens. Test physical iOS/Android browsers before claiming device-specific behavior. Preserve existing request/commerce tests; these checks supplement them.
