# Admin connection recovery

A failed connection previously produced an immediate, minimally styled message with three languages at once. Its Retry link opened `/admin`, losing the page the user had requested. The service worker now gives failed read-only navigation another chance and provides a self-contained recovery screen when failures persist.

## Navigation behavior

The worker handles same-origin GET document navigations under `/admin` only. A network exception gets two additional attempts, after 750 ms and 1,500 ms. Every attempt forwards the original Request with its credentials, destination and redirect mode. Slow pending responses have no new application timeout and are allowed to complete.

HTTP responses, including authentication failures and upstream 5xx pages, pass through unchanged. Cancelled navigation stops further attempts. Forms, writes, API/Turbo requests, storefront pages and provider authorization connection/callback URLs are excluded. Some provider GETs consume one-time state, so they must not be automatically replayed.

No authenticated page, customer data, API response or write is cached by the worker. Push notifications and their existing click behavior remain unchanged.

## Recovery screen

The 503 recovery document has `Cache-Control: no-store` and includes its own HTML, CSS, SVG icon and script. It can render without fetching styles, fonts, images or scripts. It shows one language, selected from a supported `?locale=`, then the existing public `morea_locale` cookie, then French. English and Arabic, including RTL, are supported.

Visible progress explains when the connection is being checked and how long until the next check. A manual Try again button remains available between checks. The automatic schedule starts after two seconds and increases through five, ten, twenty and thirty seconds, then stays at thirty seconds. Hidden or known-offline pages pause automatic checks; visibility and online events resume them. Manual checking remains available because the browser's offline flag is only a hint.

The screen probes the same-origin public `/up` endpoint with credentials omitted, caching disabled and a fifteen-second timeout. One probe can run at a time. A nonredirected HTTP 200 can reload the current URL, preserving its path and filters. Other responses, captive-portal redirects, timeouts and network errors keep the recovery screen open. The probe is a reachability signal, not proof that authentication or every backend dependency is healthy.

Automatic reloads have a thirty-second cooldown, recorded only as a timestamp in session storage. No destination, session token or workspace information is stored there. Manual recovery can bypass the cooldown. If storage is blocked and a probe succeeds, the screen offers explicit manual recovery rather than risk an automatic reload loop. A persisted history restoration reloads the same GET after the old page's timers and listeners have been cleaned up.

Without JavaScript, a plain link retries the current URL. This work does not queue forms, preserve unsent changes or make workspace operations available offline.

## Implementation and release

The worker template is now `app/views/pwa/service-worker.js.erb`, so Rails can embed the static `pwa/_offline.html.erb` partial as a JSON string. The public `/admin/service-worker.js` URL, worker scope and installation metadata are unchanged. The fallback response restricts resources to inline script/style and same-origin connections through its own content security policy.

Existing installed clients receive the new worker through the normal browser update process once the change is deployed and a connection is available. A client that remains completely offline cannot download this update. Nothing was deployed as part of preparing this change.

## Validation

Passed locally:

- Service-worker VM checks cover original Request identity, bounded network retries, delayed healthy responses, cancelled navigation, unchanged HTTP errors, excluded writes/APIs/provider authorization/storefront routes, and private destination data absent from the public HTML.
- Ten existing PWA installation tests pass.
- Eighteen real Chromium service-worker browser scenarios cover transient/persistent/slow connections, manual and automatic recovery to the same URL, credential-free probes, overlap prevention, paused checks, cooldown, storage denial, locale selection and responsive FR/EN/AR layouts from 320px phones through desktop and short landscape.
- Ten Rails request examples pass, including PWA metadata, compilation of the embedded document, signed-in installation UI, tenant hosts and storefront access gates.
- Changed Ruby spec lint, Rails autoloading, JavaScript syntax and whitespace checks pass. The browser harness is included in responsive CI.

Browser fixtures use synthetic HTTP pages rather than authenticated production sessions. Hidden-page and persisted-history events are simulated; real BFCache admission and physical iOS/Android weak-network behavior remain unverified. Chromium's native transport may retry a failed connection independently of the worker; exact application attempt counts are checked in the VM. The full Rails suite and full CI were not run locally.

Run the focused JavaScript checks with:

```sh
node script/admin_service_worker_test.mjs
node --test script/admin_pwa_test.mjs
node script/admin_offline_browser_test.mjs
```

Browser results and screenshots are written under ignored `tmp/admin-offline-browser/`. The browser script uses system Chromium when available or Playwright's installed Chromium.
