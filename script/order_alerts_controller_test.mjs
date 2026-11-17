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
