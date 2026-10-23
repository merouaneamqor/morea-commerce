// Run with: node script/variant_picker_smoke.mjs
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import vm from "node:vm"

const source = readFileSync(new URL("../app/javascript/controllers/variant_picker_controller.js", import.meta.url), "utf8")
const Picker = vm.runInNewContext(source.replace(/^import .*$/m, "class Controller {}").replace("export default class", "class Picker") + "\nPicker")
const element = (dataset = {}) => ({ dataset, classList: { toggle() {} }, setAttribute() {}, textContent: "", disabled: false })
const picker = new Picker()
picker.variantsValue = [
  { id: 1, size: "S", color: "Black", stock: 0, price: "100 MAD", price_cents: 10000 },
  { id: 2, size: "M", color: "Black", stock: 2, price: "120 MAD", price_cents: 12000 },
  { id: 3, size: "M", color: "White", stock: 0, price: "140 MAD", price_cents: 14000 }
]
picker.trackInventoryValue = true
picker.availableLabelValue = "Available"
picker.unavailableLabelValue = "Sold out"
picker.orderLabelValue = "Order now"
picker.compareAtValue = 13000
picker.sizeButtonTargets = [element({ size: "S" }), element({ size: "M" })]
picker.colorButtonTargets = [element({ color: "Black" }), element({ color: "White" })]
picker.priceTargets = [element(), element()]
picker.comparePriceTargets = [element()]
picker.availabilityTargets = [element()]
picker.purchaseButtonTargets = Array.from({ length: 4 }, () => element())
picker.orderLabelTargets = [element(), element()]
picker.variantIdTarget = element()
picker.hasVariantIdTarget = true
picker.hasColorLabelTarget = false
picker.dispatch = (_name, event) => { picker.lastVariant = event.detail.variant }
picker.connect()
assert.equal(picker.variantIdTarget.value, 2, "Start with an available variant")
assert.ok(picker.purchaseButtonTargets.every((button) => !button.disabled))
assert.ok(picker.priceTargets.every((price) => price.textContent === "120 MAD"), "Desktop and mobile prices agree")
assert.equal(picker.lastVariant.id, 2, "Notify the gallery about the selection")
picker.selectColor({ preventDefault() {}, currentTarget: { dataset: { color: "White" } } })
assert.equal(picker.availabilityTargets[0].textContent, "Sold out")
assert.ok(picker.purchaseButtonTargets.every((button) => button.disabled), "Disable every purchase button for a sold-out variant")
assert.equal(picker.comparePriceTargets[0].hidden, true, "Do not show a discount above the comparison price")
let prevented = false
picker.validate({ preventDefault() { prevented = true } })
assert.ok(prevented, "Block submission of an unavailable selection")
picker.trackInventoryValue = false
picker.render()
assert.ok(picker.purchaseButtonTargets.every((button) => !button.disabled), "Untracked inventory remains purchasable")
picker.trackInventoryValue = true
picker.selectSize({ preventDefault() {}, currentTarget: { dataset: { size: "S" } } })
assert.equal(picker.variantIdTarget.value, 1, "A color absent from the selected size falls back to an existing combination")
assert.ok(picker.purchaseButtonTargets.every((button) => button.disabled))
picker.variantsValue.forEach((variant) => { variant.stock = 0 })
picker.connect()
assert.ok(picker.purchaseButtonTargets.every((button) => button.disabled), "An entirely sold-out product stays disabled")
picker.variantsValue = []
picker.connect()
console.log("Variant selection: stock, mobile/desktop prices, comparison price, gallery event and submission checks passed")
