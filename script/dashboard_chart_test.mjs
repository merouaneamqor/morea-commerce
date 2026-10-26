// Exercise Chart.js ownership across Stimulus/Turbo page transitions, without a browser.
import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"

const instances = []
class FakeChart {
  constructor(canvas, config) { this.canvas = canvas; this.config = config; this.destroyed = 0; instances.push(this) }
  destroy() { this.destroyed += 1 }
}
const listeners = new Map()
globalThis.__chartTest = FakeChart
globalThis.document = {
  documentElement: { lang: "en" },
  addEventListener(name, callback) { listeners.set(name, callback) },
  removeEventListener(name, callback) { if (listeners.get(name) === callback) listeners.delete(name) }
}
globalThis.window = { matchMedia: () => ({ matches: true }) }
globalThis.getComputedStyle = () => ({ color: "rgb(24, 24, 24)", backgroundColor: "rgb(255, 255, 255)" })
const source = (await readFile(new URL("../app/javascript/controllers/dashboard_chart_controller.js", import.meta.url), "utf8"))
  .replace('import { Controller } from "@hotwired/stimulus"', "class Controller {}")
  .replace('import Chart from "chart.js/auto"', "const Chart = globalThis.__chartTest")
const { default: Controller } = await import(`data:text/javascript;base64,${Buffer.from(source).toString("base64")}`)
const controller = new Controller()
controller.element = {}
controller.canvasTarget = {}
controller.currencyValue = "MAD"
controller.configValue = { type: "line", data: { labels: ["01/10", "02/10"], datasets: [{ label: "Order value", data: [0, 123.45] }] } }
controller.connect()
assert.equal(instances.length, 1)
assert.equal(instances[0].config.options.animation, false)
assert.equal(instances[0].config.options.responsive, true)
assert.equal(instances[0].config.options.maintainAspectRatio, false)
assert.equal(instances[0].config.data.datasets[0].borderColor, "rgb(24, 24, 24)")
assert.equal(instances[0].config.options.plugins.tooltip.callbacks.label({ dataset: { label: "Order value" }, parsed: { y: 123.45 } }), "Order value: 123.45 MAD")
assert.equal(controller.configValue.data.datasets[0].borderColor, undefined, "rendering must not mutate Stimulus values")
listeners.get("turbo:before-cache")()
assert.equal(instances[0].destroyed, 1)
controller.disconnect()
assert.equal(instances[0].destroyed, 1, "cached chart must not be destroyed twice")
assert.equal(listeners.size, 0)
controller.connect()
assert.equal(instances.length, 2)
controller.connect()
assert.equal(instances[1].destroyed, 1, "repeat connection must release prior canvas")
controller.disconnect()
assert.equal(instances[2].destroyed, 1)
assert.equal(listeners.size, 0)

document.documentElement.dir = "rtl"
controller.configValue = { type: "pie", data: { labels: ["New", "Delivered"], datasets: [{ data: [1, 3] }] } }
controller.connect()
assert.equal(controller.chart.config.options.plugins.legend.display, false)
assert.equal(controller.chart.config.options.plugins.legend.rtl, true)
assert.equal(controller.chart.config.options.plugins.tooltip.textDirection, "rtl")
assert.equal(controller.chart.config.options.plugins.tooltip.callbacks.label({ label: "Delivered", dataset: { data: [1, 3] }, raw: 3 }), "Delivered: 3 (75%)")
assert.equal(controller.chart.config.options.plugins.tooltip.callbacks.label({ label: "New", dataset: { data: [0, 0] }, raw: 0 }), "New: 0 (0%)")
controller.disconnect()
assert.equal(listeners.size, 0)
console.log("Dashboard Chart.js lifecycle: passed")
