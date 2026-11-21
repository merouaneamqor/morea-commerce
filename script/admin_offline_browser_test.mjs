import assert from "node:assert/strict"
import fs from "node:fs/promises"
import { existsSync } from "node:fs"
import http from "node:http"
import path from "node:path"
import { chromium } from "playwright"

// Real service worker and self-contained offline partial, served by a synthetic
// same-origin HTTP fixture. No Rails session, database, or production site.
const output = path.join(process.cwd(), "tmp/admin-offline-browser")
await fs.mkdir(output, { recursive: true })
let mode = "healthy"
let failuresLeft = 0
let navigationRequests = 0
let writes = 0
let xhrRequests = 0
let healthOK = false
let healthDelay = 0
let healthRequests = []
const fixturePage = '<!doctype html><meta charset="utf-8"><title>Synthetic admin</title><h1 id="native">Synthetic private workspace</h1><script>navigator.serviceWorker.register("/admin/service-worker.js",{scope:"/admin/"})</script>'
const server = http.createServer(async (request, response) => {
  try {
    const url = new URL(request.url, "http://localhost")
    response.setHeader("Cache-Control", "no-store")
    if (url.pathname === "/admin/service-worker.js") {
      const partial = await fs.readFile("app/views/pwa/_offline.html.erb", "utf8")
      let worker = await fs.readFile("app/views/pwa/service-worker.js.erb", "utf8")
      worker = worker.replace(/<%=\s*render\("pwa\/offline",\s*formats:\s*\[\s*:html\s*\]\)\.to_json\.html_safe\s*%>/, JSON.stringify(partial))
      assert.ok(!worker.includes("<%"), "Fixture must render every service-worker ERB expression")
      response.setHeader("Content-Type", "text/javascript")
      response.end(worker)
      return
    }
    if (url.pathname === "/up") {
      healthRequests.push({ cookie: request.headers.cookie, cacheControl: request.headers["cache-control"] })
      await new Promise(resolve => setTimeout(resolve, healthDelay))
      response.writeHead(healthOK ? 200 : 503, { "Content-Type": "text/plain" })
      response.end(healthOK ? "ok" : "unavailable")
      return
    }
    if (request.method !== "GET") { writes++; response.writeHead(500); response.end("synthetic write failure"); return }
    if (url.pathname === "/admin/xhr") { xhrRequests++; response.writeHead(500); response.end("synthetic XHR failure"); return }
    if (url.pathname === "/admin/orders") {
      navigationRequests++
      if (mode === "persistent" || mode === "transient" && failuresLeft-- > 0) { request.socket.destroy(); return }
      if (mode === "slow") await new Promise(resolve => setTimeout(resolve, 2500))
      if (mode === "http503") { response.writeHead(503, { "Content-Type": "text/html" }); response.end('<h1 id="upstream">Synthetic server unavailable</h1>'); return }
    }
    response.setHeader("Content-Type", "text/html; charset=utf-8")
    response.end(fixturePage)
  } catch (error) { response.writeHead(500); response.end(String(error)) }
})
await new Promise(resolve => server.listen(0, "127.0.0.1", resolve))
const origin = `http://127.0.0.1:${server.address().port}`
const executablePath = process.env.CHROMIUM_PATH || (existsSync("/usr/bin/chromium") ? "/usr/bin/chromium" : undefined)
const browser = await chromium.launch({ ...(executablePath ? { executablePath } : {}), headless: true })
let context
let page
const results = []
async function check(name, action) {
  if (process.env.OFFLINE_CHECK && !name.includes(process.env.OFFLINE_CHECK)) return
  try {
    mode = "healthy"; failuresLeft = 0; navigationRequests = 0; writes = 0; xhrRequests = 0; healthOK = false; healthDelay = 0; healthRequests = []
    context = await browser.newContext()
    page = await context.newPage()
    await page.goto(origin + "/admin/setup")
    await page.evaluate(async () => {
      let timeout
      try {
        await Promise.race([
          (async () => {
            await navigator.serviceWorker.ready
            if (!navigator.serviceWorker.controller) await new Promise(resolve => navigator.serviceWorker.addEventListener("controllerchange", resolve, { once: true }))
          })(),
          new Promise((_, reject) => { timeout = setTimeout(() => reject(new Error("Fixture worker did not activate/control the page")), 10000) })
        ])
      } finally { clearTimeout(timeout) }
    })
    await action()
    results.push({ name, passed: true })
    console.log(`PASS ${name}`)
  } catch (error) {
    results.push({ name, passed: false, error: String(error) })
    console.error(`FAIL ${name}: ${error}`)
    await page?.screenshot({ path: path.join(output, `failure-${results.length}.png`), fullPage: true }).catch(() => {})
  } finally { await context?.close() }
}
const target = "/admin/orders?locale=en&status=confirmed&page=3"
async function fallback(url = target) {
  mode = "persistent"
  const response = await page.goto(origin + url)
  assert.equal(response.status(), 503)
  assert.match(response.headers()["cache-control"], /no-store/)
  await page.locator("[data-offline-retry]").waitFor()
}
try {
  await check("healthy slow navigation remains a native response", async () => {
    mode = "slow"
    const started = Date.now()
    const response = await page.goto(origin + target)
    assert.equal(response.status(), 200)
    assert.ok(Date.now() - started >= 2400)
    await page.locator("#native").waitFor()
    assert.equal(navigationRequests, 1)
  })
  await check("transient transport failures recover before fallback", async () => {
    mode = "transient"; failuresLeft = 2
    const response = await page.goto(origin + target)
    assert.equal(response.status(), 200)
    await page.locator("#native").waitFor()
    assert.ok(navigationRequests >= 3)
  })
  await check("upstream HTTP errors remain native and are not retried", async () => {
    mode = "http503"
    const response = await page.goto(origin + target)
    assert.equal(response.status(), 503)
    await page.locator("#upstream").waitFor()
    assert.equal(navigationRequests, 1)
  })
  await check("persistent failure offers manual retry to the same path and query", async () => {
    await fallback()
    assert.equal(new URL(page.url()).pathname + new URL(page.url()).search, target)
    const requests = []
    page.on("request", request => requests.push(request.url()))
    mode = "healthy"; healthOK = true
    await page.locator("[data-offline-retry]").click()
    await page.locator("#native").waitFor({ timeout: 15000 })
    assert.equal(new URL(page.url()).pathname + new URL(page.url()).search, target)
    assert.ok(requests.every(url => new URL(url).origin === origin))
  })
  await check("browser offline then online automatically restores the requested page", async () => {
    await context.setOffline(true)
    await fallback()
    mode = "healthy"; healthOK = true
    await context.setOffline(false)
    await page.locator("#native").waitFor({ timeout: 20000 })
    assert.equal(new URL(page.url()).pathname + new URL(page.url()).search, target)
  })
  await check("health checks omit credentials and overlap is prevented", async () => {
    await context.addCookies([{ name: "synthetic_session", value: "synthetic-private", url: origin }])
    await fallback()
    healthDelay = 1500
    const before = healthRequests.length
    await page.locator("[data-offline-retry]").click()
    await page.evaluate(() => { document.querySelector("[data-offline-retry]").click(); window.dispatchEvent(new Event("online")) })
    await page.waitForTimeout(500)
    assert.ok(healthRequests.length - before <= 1)
    await page.waitForTimeout(1600)
    assert.ok(healthRequests.length > 0)
    assert.ok(healthRequests.every(request => !request.cookie))
    assert.ok(healthRequests.every(request => /no-cache|no-store/.test(request.cacheControl || "")))
  })
  await check("worker does not cache private pages or intercept writes and XHR", async () => {
    const outcomes = await page.evaluate(async () => {
      const results = []
      for (const [url, options] of [["/admin/orders", { method: "POST", body: "synthetic" }], ["/admin/xhr", {}]]) {
        const response = await fetch(url, options)
        results.push({ status: response.status, body: await response.text() })
      }
      return { results, caches: await caches.keys() }
    })
    assert.deepEqual(outcomes.results, [{status: 500, body: "synthetic write failure"}, {status: 500, body: "synthetic XHR failure"}])
    assert.equal(writes, 1)
    assert.equal(xhrRequests, 1)
    assert.deepEqual(outcomes.caches, [])
    await context.setOffline(true)
    await fallback()
    assert.equal(await page.locator("#native").count(), 0)
  })
  await check("hidden pages pause automatic probes until visible", async () => {
    await page.addInitScript(() => { window.fixtureHidden = true; Object.defineProperty(document, "visibilityState", {get: () => window.fixtureHidden ? "hidden" : "visible"}) })
    await fallback()
    await page.waitForTimeout(2500)
    assert.equal(healthRequests.length, 0)
    mode = "healthy"; healthOK = true
    await page.evaluate(() => { window.fixtureHidden = false; document.dispatchEvent(new Event("visibilitychange")) })
    await page.locator("#native").waitFor({timeout: 15000})
  })
  await check("recent automatic reload cooldown does not prevent manual recovery", async () => {
    await page.evaluate(() => sessionStorage.setItem("seallo:offline:last-reload", String(Date.now())))
    await fallback()
    const before = navigationRequests
    healthOK = true
    await page.waitForTimeout(3000)
    assert.equal(navigationRequests, before)
    mode = "healthy"
    await page.locator("[data-offline-retry]").click()
    await page.locator("#native").waitFor({timeout: 15000})
  })
  await check("public storefront navigation is outside the admin worker scope", async () => {
    await context.setOffline(true)
    let failed = false
    try { await page.goto(origin + "/fr/collections") } catch { failed = true }
    assert.equal(failed, true)
  })
  await check("locale defaults to French and follows the saved public preference", async () => {
    await fallback("/admin/orders?status=new")
    assert.equal(await page.locator("html").getAttribute("lang"), "fr")
    mode = "healthy"
    await page.goto(origin + "/admin/setup")
    await context.addCookies([{name: "morea_locale", value: "ar", url: origin}])
    await fallback("/admin/orders?status=new")
    assert.equal(await page.locator("html").getAttribute("lang"), "ar")
    await fallback("/admin/orders?locale=en")
    assert.equal(await page.locator("html").getAttribute("lang"), "en")
  })
  await check("blocked session storage offers safe manual recovery", async () => {
    await page.addInitScript(() => {
      Storage.prototype.getItem = () => { throw new DOMException("Synthetic storage denial", "SecurityError") }
      Storage.prototype.setItem = () => { throw new DOMException("Synthetic storage denial", "SecurityError") }
    })
    await fallback()
    const before = navigationRequests
    healthOK = true
    await page.waitForFunction(() => document.body.dataset.offlineState === "ready", null, {timeout: 15000})
    assert.equal(navigationRequests, before)
    mode = "healthy"
    await page.locator("[data-offline-retry]").click()
    await page.locator("#native").waitFor({timeout: 15000})
    assert.equal(new URL(page.url()).pathname + new URL(page.url()).search, target)
  })
  await check("persisted pageshow event restores the original GET after pagehide cleanup", async () => {
    await fallback()
    const before = healthRequests.length
    await page.evaluate(() => window.dispatchEvent(new PageTransitionEvent("pagehide", {persisted: true})))
    await page.waitForTimeout(2200)
    assert.equal(healthRequests.length, before)
    mode = "healthy"
    await page.evaluate(() => window.dispatchEvent(new PageTransitionEvent("pageshow", {persisted: true})))
    await page.locator("#native").waitFor({timeout: 15000})
    assert.equal(new URL(page.url()).pathname + new URL(page.url()).search, target)
  })
  for (const [width, height, locale] of [[320, 640, "fr"], [375, 812, "en"], [375, 812, "ar"], [1440, 900, "fr"], [812, 375, "ar"]]) {
    await check(`offline layout ${width}x${height} ${locale}`, async () => {
      await page.setViewportSize({ width, height })
      await fallback(`/admin/orders?locale=${locale}&status=confirmed`)
      const geometry = await page.evaluate(() => ({ width: document.documentElement.scrollWidth, viewport: innerWidth, language: document.documentElement.lang, direction: document.documentElement.dir, assets: [...document.querySelectorAll('[src],link[rel="stylesheet"]')].length, button: (()=>{const b=document.querySelector("[data-offline-retry]").getBoundingClientRect();return {left:b.left,right:b.right,height:b.height}})() }))
      assert.equal(geometry.language, locale)
      assert.equal(geometry.direction === "rtl", locale === "ar")
      assert.ok(geometry.width <= geometry.viewport)
      assert.ok(geometry.button.left >= 0 && geometry.button.right <= width)
      assert.ok(geometry.button.height >= 44)
      assert.equal(geometry.assets, 0)
      await page.locator("[data-offline-retry]").scrollIntoViewIfNeeded()
      await page.screenshot({ path: path.join(output, `offline-${width}-${height}-${locale}.png`), fullPage: true })
    })
  }
} finally {
  await browser.close()
  await new Promise(resolve => server.close(resolve))
  await fs.writeFile(path.join(output, process.env.OFFLINE_CHECK ? "results-filtered.json" : "results.json"), JSON.stringify({ mode: "real service worker, synthetic HTTP fixture", checks: results.length, results }, null, 2))
}
console.log(`${results.filter(result=>result.passed).length} passed; ${results.filter(result=>!result.passed).length} failed`)
if (results.some(result => !result.passed)) process.exitCode = 1
