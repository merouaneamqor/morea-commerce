import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = await readFile(new URL("../app/javascript/admin_pwa.js", import.meta.url), "utf8")
const { setupAdminPwa, isIosDevice } = await import(`data:text/javascript;base64,${Buffer.from(source).toString("base64")}`)
const tick = () => new Promise((resolve) => setImmediate(resolve))

function harness({ marker = true, path = "/admin", standalone = false, blockedStorage = false, readyState = "complete", ios = false, savedDismissal = 0, legacyStandalone = false } = {}) {
  const handlers = {}
  const nodes = Object.fromEntries(["instructions", "install", "dismiss", "ios", "other"].map((key) => [key, {
    hidden: key === "instructions", attributes: {},
    setAttribute(name, value) { this.attributes[name] = value },
    closest(selector) {
      if (selector === "[data-admin-pwa]") return element
      return selector === `[data-admin-pwa-${key}]` ? this : null
    }
  }]))
  const element = { hidden: true, querySelector: (selector) => nodes[selector.match(/data-admin-pwa-(.*)\]/)[1]] }
  let current = marker ? element : null
  let time = 1_000_000_000
  let registered = []
  const values = new Map(savedDismissal ? [["seallo.admin.install.dismissedAt", String(savedDismissal)]] : [])
  const listen = (name, callback) => { (handlers[name] ||= []).push(callback) }
  const document = { readyState, querySelector: () => current, addEventListener: listen }
  const window = {
    location: { pathname: path }, isSecureContext: true,
    addEventListener: listen, matchMedia: () => ({ matches: standalone })
  }
  const navigator = {
    userAgent: ios ? "iPhone" : "Android", platform: "", maxTouchPoints: 0, standalone: legacyStandalone,
    serviceWorker: { register: (...args) => { registered.push(args); return Promise.resolve() } }
  }
  const storage = () => {
    if (blockedStorage) throw new Error("Storage disabled")
    return { getItem: (key) => values.get(key), setItem: (key, value) => values.set(key, value) }
  }
  setupAdminPwa({ window, document, navigator, storage, now: () => time })
  return {
    element, nodes, handlers, registered, values, window,
    dispatch: (name, event = {}) => handlers[name]?.forEach((callback) => callback(event)),
    click(key) { this.dispatch("click", { target: nodes[key] }) },
    mount: () => { current = element }, advance: (ms) => { time += ms }
  }
}

test("captures native installation before page load but prompts only after an install click", async () => {
  const app = harness({ marker: false, readyState: "loading" })
  let prevented = 0
  let prompts = 0
  app.dispatch("beforeinstallprompt", {
    preventDefault() { prevented++ },
    prompt() { prompts++; return Promise.resolve() },
    userChoice: Promise.resolve({ outcome: "accepted" })
  })
  assert.equal(prevented, 1)
  assert.equal(prompts, 0)
  assert.equal(app.registered.length, 0)
  app.mount()
  app.dispatch("turbo:load")
  assert.equal(app.element.hidden, false)
  app.click("install")
  assert.equal(prompts, 1)
  await tick()
  assert.equal(app.element.hidden, true)
  app.dispatch("turbo:load")
  assert.equal(app.element.hidden, true)
})

test("iOS and desktop-mode iPads receive manual install instructions", () => {
  assert.equal(isIosDevice({ userAgent: "Macintosh", platform: "MacIntel", maxTouchPoints: 5 }), true)
  assert.equal(isIosDevice({ userAgent: "Macintosh", platform: "MacIntel", maxTouchPoints: 0 }), false)
  const app = harness({ ios: true })
  assert.equal(app.nodes.ios.hidden, false)
  assert.equal(app.nodes.other.hidden, true)
  app.click("install")
  assert.equal(app.nodes.instructions.hidden, false)
  assert.equal(app.nodes.install.attributes["aria-expanded"], "true")
  app.click("install")
  assert.equal(app.nodes.instructions.hidden, true)
})

test("Android falls back to browser-menu instructions without a native event", () => {
  const app = harness()
  app.click("install")
  assert.equal(app.nodes.instructions.hidden, false)
  assert.equal(app.nodes.other.hidden, false)
  assert.equal(app.nodes.ios.hidden, true)
})

test("dismissal persists for seven days and works with blocked localStorage", () => {
  for (const blockedStorage of [false, true]) {
    const app = harness({ blockedStorage })
    app.click("dismiss")
    assert.equal(app.element.hidden, true)
    app.dispatch("turbo:load")
    assert.equal(app.element.hidden, true)
    app.advance(7 * 24 * 60 * 60 * 1000)
    app.dispatch("turbo:load")
    assert.equal(app.element.hidden, false)
  }
})

test("native dismissal enters cooldown instead of repeatedly opening native prompts", async () => {
  const app = harness()
  let prompts = 0
  app.dispatch("beforeinstallprompt", {
    preventDefault() {}, prompt() { prompts++; return Promise.resolve() },
    userChoice: Promise.resolve({ outcome: "dismissed" })
  })
  app.click("install")
  await tick()
  assert.equal(prompts, 1)
  assert.equal(app.element.hidden, true)
  app.dispatch("turbo:load")
  assert.equal(app.element.hidden, true)
})

test("standalone mode and appinstalled hide the prompt across navigation", () => {
  const standalone = harness({ standalone: true })
  assert.equal(standalone.element.hidden, true)
  assert.equal(harness({ legacyStandalone: true }).element.hidden, true)
  const app = harness()
  app.dispatch("appinstalled")
  app.dispatch("turbo:load")
  assert.equal(app.element.hidden, true)
})

test("logged-out and storefront pages do not show UI or register the worker", () => {
  const loggedOut = harness({ marker: false, path: "/admin/login" })
  assert.equal(loggedOut.element.hidden, true)
  assert.equal(loggedOut.registered.length, 0)
  for (const path of ["/fr", "/administrator"]) {
    const app = harness({ path })
    let prevented = false
    app.dispatch("beforeinstallprompt", { preventDefault() { prevented = true } })
    assert.equal(prevented, false)
    assert.equal(app.element.hidden, true)
    assert.equal(app.registered.length, 0)
  }
})

test("Turbo visits keep one registration and reset cached instructions", () => {
  const app = harness()
  app.click("install")
  app.dispatch("turbo:before-cache")
  assert.equal(app.element.hidden, true)
  assert.equal(app.nodes.instructions.hidden, true)
  app.dispatch("turbo:load")
  app.dispatch("turbo:load")
  assert.equal(app.element.hidden, false)
  assert.equal(app.registered.length, 1)
  assert.deepEqual(app.registered[0], ["/admin/service-worker.js", { scope: "/admin" }])
  assert.equal(app.handlers.click.length, 1)
})

test("saved dismissal suppresses a new page load until its cooldown expires", () => {
  const app = harness({ savedDismissal: 1_000_000_000 })
  assert.equal(app.element.hidden, true)
  app.advance(7 * 24 * 60 * 60 * 1000)
  app.dispatch("turbo:load")
  assert.equal(app.element.hidden, false)
})

test("failed native prompts fall back to manual instructions", async () => {
  const app = harness()
  app.dispatch("beforeinstallprompt", {
    preventDefault() {}, prompt() { return Promise.reject(new Error("Native prompt unavailable")) }
  })
  app.click("install")
  await tick()
  assert.equal(app.nodes.instructions.hidden, false)
  assert.equal(app.element.hidden, false)
})
