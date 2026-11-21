import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import vm from "node:vm"

const worker = await readFile(new URL("../app/views/pwa/service-worker.js.erb", import.meta.url), "utf8")
const offline = await readFile(new URL("../app/views/pwa/_offline.html.erb", import.meta.url), "utf8")
const source = worker.replace('<%= render("pwa/offline", formats: [ :html ]).to_json.html_safe %>', JSON.stringify(offline))
function harness(fetch) {
  const handlers = new Map()
  const delays = []
  vm.runInNewContext(source, {
    self: { addEventListener: (event, handler) => handlers.set(event, handler), location: { origin: "https://example.test" } },
    URL, Response, fetch,
    setTimeout(callback, delay) { delays.push(delay); queueMicrotask(callback) }
  })
  return {
    delays,
    dispatch(path, attributes = {}) {
      let promise
      const request = { url: `https://example.test${path}`, method: "GET", mode: "navigate", ...attributes }
      handlers.get("fetch")({ request, respondWith: (response) => { promise = response } })
      return { request, promise }
    }
  }
}
const live = new Response("authenticated response")
let requested
let calls = 0
const online = harness(async request => { requested = request; calls++; return live })
const admin = online.dispatch("/admin")
assert.equal(await admin.promise, live)
assert.equal(calls, 1)
assert.equal(requested, admin.request, "forwards original credentials-bearing request without rebuilding it")
for (const [path, attributes] of [
  ["/admin/orders", { method: "POST" }], ["/admin/orders", { method: "PATCH" }], ["/admin/orders", { method: "DELETE" }],
  ["/admin/orders", { mode: "cors" }], ["/admin/youcan/callback?code=synthetic", {}],
  ["/admin/youcan/connect", {}], ["/admin/youcan/callback.json?code=synthetic", {}],
  ["/admin/youcan/connect.html", {}], ["/admin/seallo/connect", {}], ["/admin/woocommerce/connect", {}], ["/fr/products", {}], ["/administrator", {}],
  ["/admin", { url: "https://foreign.test/admin" }], ["/up", {}]
]) assert.equal(online.dispatch(path, attributes).promise, undefined, "does not intercept writes, APIs, probes or storefronts")
assert.equal(calls, 1)

const attempts = []
const intermittent = harness(async request => {
  attempts.push(request)
  if (attempts.length < 3) throw new TypeError("network unavailable")
  return live
})
const retried = intermittent.dispatch("/admin/orders?status=new&locale=ar")
assert.equal(await retried.promise, live)
assert.equal(attempts.length, 3)
assert.ok(attempts.every(request => request === retried.request), "retries retain the original destination and credentials")
assert.deepEqual(intermittent.delays, [750, 1500])

let failures = 0
const disconnected = harness(async () => { failures++; throw new TypeError("offline") })
const fallback = await disconnected.dispatch("/admin/orders?private-filter=synthetic").promise
assert.equal(failures, 3)
assert.equal(fallback.status, 503)
assert.match(fallback.headers.get("cache-control"), /no-store/)
assert.match(fallback.headers.get("content-security-policy"), /connect-src 'self'/)
const html = await fallback.text()
assert.ok(html.includes("data-offline-retry"))
assert.ok(!html.includes("private-filter"), "private destination data is not embedded in the public recovery document")
assert.ok(!html.includes('href="/admin"'), "retry must not send the user back to the dashboard")

for (const status of [401, 403, 404, 500, 502, 503, 504]) {
  let count = 0
  const response = new Response("server response", {status})
  const server = harness(async () => { count++; return response })
  assert.equal(await server.dispatch("/admin/orders").promise, response)
  assert.equal(count, 1, "does not replay HTTP errors or hide authentication failures")
}

let finish
const pending = harness(() => new Promise(resolve => { finish = resolve }))
const slow = pending.dispatch("/admin/orders")
assert.deepEqual(pending.delays, [], "a pending slow response is not replaced by a short timeout")
finish(live)
assert.equal(await slow.promise, live)

let abortedAttempts = 0
const cancelled = harness(async () => { abortedAttempts++; throw new DOMException("Cancelled", "AbortError") })
await assert.rejects(cancelled.dispatch("/admin/orders", {signal:{aborted:true}}).promise, {name:"AbortError"})
assert.equal(abortedAttempts, 1, "navigation cancelled by the user must not keep retrying")
console.log("Admin service worker: retry, privacy, slow connection and request-boundary checks passed")
