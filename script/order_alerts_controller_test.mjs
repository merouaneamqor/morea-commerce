import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = (await readFile(new URL("../app/javascript/controllers/order_alerts_controller.js", import.meta.url), "utf8"))
  .replace('import { Controller } from "@hotwired/stimulus"', 'class Controller {}')
const { default: Alerts } = await import(`data:text/javascript;base64,${Buffer.from(source).toString("base64")}`)

function serviceWorker(value) {
  Object.defineProperty(globalThis, "navigator", { configurable: true, value: { serviceWorker: value } })
}

test("seller pages use a root worker without awaiting a legacy document registration", async () => {
  const registration = { active: {} }
  serviceWorker({
    register: async (url, options) => {
      assert.equal(url, "/admin/service-worker.js")
      assert.equal(options.scope, "/")
      return registration
    },
    get ready() { throw new Error("Document readiness must not select the old /admin worker") }
  })
  assert.equal(await new Alerts().registration(), registration)
})

test("subscription waits for its own worker activation on first install", async () => {
  let change
  let removed = false
  const worker = {
    state: "installing",
    addEventListener: (name, callback) => { change = callback },
    removeEventListener: () => { removed = true }
  }
  const registration = { installing: worker }
  serviceWorker({ register: async () => registration })
  let completed = false
  const pending = new Alerts().registration().then((result) => { completed = true; return result })
  await Promise.resolve()
  assert.equal(completed, false)
  worker.state = "activated"
  change()
  assert.equal(await pending, registration)
  assert.equal(removed, true)
})

test("failed activation rejects instead of leaving the alert toggle pending", async () => {
  const worker = { state: "redundant", addEventListener() {}, removeEventListener() {} }
  serviceWorker({ register: async () => ({ installing: worker }) })
  await assert.rejects(new Alerts().registration(), /activation failed/)
})

function settingsController() {
  const controller = new Alerts()
  controller.toggleTarget = { disabled: false }
  controller.hasStatusTarget = true
  controller.statusTarget = { textContent: "" }
  controller.errorLabelValue = "Connection failed"
  controller.render = (on, options) => { controller.enabled = on; controller.lastRender = options }
  controller.chime = () => {}
  controller.applicationServerKey = () => new Uint8Array()
  return controller
}

test("settings activation requests permission from the click and saves before enabling", async () => {
  const alerts = settingsController()
  let requested = false
  globalThis.Notification = { requestPermission: async () => { requested = true; return "granted" } }
  alerts.registration = async () => ({ pushManager: { subscribe: async () => ({ toJSON: () => ({ endpoint: "synthetic" }) }) } })
  alerts.send = async (method, body) => { assert.equal(method, "POST"); assert.equal(body.endpoint, "synthetic"); assert.equal(alerts.enabled, undefined) }
  const pending = alerts.toggle()
  assert.equal(requested, true)
  assert.equal(alerts.toggleTarget.disabled, true)
  await pending
  assert.equal(alerts.enabled, true)
  assert.equal(alerts.toggleTarget.disabled, false)
})

test("settings disable removes server delivery and browser subscription", async () => {
  const alerts = settingsController()
  alerts.enabled = true
  const calls = []
  alerts.registration = async () => ({ pushManager: { getSubscription: async () => ({ endpoint: "synthetic", unsubscribe: async () => { calls.push("unsubscribe"); return true } }) } })
  alerts.send = async (method) => { calls.push(method) }
  await alerts.toggle()
  assert.deepEqual(calls, ["DELETE", "unsubscribe"])
  assert.equal(alerts.enabled, false)
})

test("failed disable keeps the enabled state and exposes a retryable error", async () => {
  const alerts = settingsController()
  alerts.enabled = true
  alerts.disable = async () => { throw new Error("offline") }
  await alerts.toggle()
  assert.equal(alerts.enabled, true)
  assert.equal(alerts.statusTarget.textContent, "Connection failed")
  assert.equal(alerts.toggleTarget.disabled, false)
})

test("permission denial never creates a push subscription", async () => {
  const alerts = settingsController()
  globalThis.Notification = { requestPermission: async () => "denied" }
  alerts.registration = () => { throw new Error("must not subscribe") }
  await alerts.toggle()
  assert.equal(alerts.enabled, false)
  assert.equal(alerts.lastRender.blocked, true)
})
