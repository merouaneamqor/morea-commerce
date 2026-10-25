import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import vm from "node:vm"

const handlers = new Map()
let online = true
let requested
const live = new Response("authenticated response")
vm.runInNewContext(await readFile(new URL("../app/views/pwa/service-worker.js", import.meta.url), "utf8"), {
  self: { addEventListener: (event, handler) => handlers.set(event, handler), location: { origin: "https://example.test" } },
  URL, Response,
  fetch: async (request) => { requested = request; if (!online) throw new TypeError("offline"); return live }
})
function dispatch(path, attributes = {}) {
  let promise
  const request = { url: `https://example.test${path}`, method: "GET", mode: "navigate", ...attributes }
  handlers.get("fetch")({ request, respondWith: (response) => { promise = response } })
  return { request, promise }
}
const admin = dispatch("/admin")
assert.equal(await admin.promise, live)
assert.equal(requested, admin.request, "forwards original credentials-bearing request without rebuilding it")
for (const [path, attributes] of [
  ["/admin/orders", { method: "POST" }], ["/admin/orders", { mode: "cors" }],
  ["/fr/products", {}], ["/administrator", {}],
  ["/admin", { url: "https://foreign.test/admin" }]
]) assert.equal(dispatch(path, attributes).promise, undefined, "does not intercept writes, APIs or storefronts")
online = false
const offline = await dispatch("/admin/orders").promise
assert.equal(offline.status, 503)
assert.match(offline.headers.get("cache-control"), /no-store/)
assert.match(await offline.text(), /Connection required/)
console.log("Admin service worker checks passed")
