// Run with: node script/variant_picker_smoke.mjs
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import vm from "node:vm"

const source = readFileSync(new URL("../app/javascript/controllers/variant_picker_controller.js", import.meta.url), "utf8")
const fakeDocument = {
  documentElement: { classList: { add() {}, remove() {} } },
  addEventListener() {},
  removeEventListener() {},
  getElementById() { return null }
}
const Picker = vm.runInNewContext(
  source.replace(/^import .*$/m, "class Controller {}").replace("export default class", "class Picker") + "\nPicker",
  {
    clearTimeout,
    setTimeout,
    document: fakeDocument,
    requestAnimationFrame: (cb) => cb()
  }
)
const element = (dataset = {}) => ({ dataset, classList: { toggle() {}, add() {}, remove() {} }, setAttribute() {}, textContent: "", disabled: false, hidden: false, focus() {}, scrollIntoView() {} })
const picker = new Picker()
picker.variantsValue = [
  { id: 1, size: "S", color: "Black", stock: 0, price: "100 DH", price_cents: 10000 },
  { id: 2, size: "M", color: "Black", stock: 2, price: "120 DH", price_cents: 12000 },
  { id: 3, size: "M", color: "White", stock: 0, price: "140 DH", price_cents: 14000 }
]
picker.trackInventoryValue = true
picker.requireSizeValue = false
picker.availableLabelValue = "Available"
picker.unavailableLabelValue = "Sold out"
picker.orderLabelValue = "Order"
picker.orderWithPriceLabelValue = "Order — %{price}"
picker.chooseSizeLabelValue = "Choose my size"
picker.selectionSummaryLabelValue = "%{color} · Size %{size}"
picker.selectionSummarySizeLabelValue = "Size %{size}"
picker.compareAtValue = 13000
picker.compareAtDisplayValue = "130 DH"
picker.saveAmountLabelValue = "%{amount} off"
picker.priceRevertsLabelValue = "After %{when}, the price goes back to %{compare}."
picker.saleUntilWhenValue = ""
picker.savingsDisplayValue = "10 DH"
picker.sizeButtonTargets = [element({ size: "S" }), element({ size: "M" })]
picker.colorButtonTargets = [element({ color: "Black" }), element({ color: "White" })]
picker.priceTargets = [element(), element()]
picker.comparePriceTargets = [element()]
picker.savingsTarget = element()
picker.saleUntilTarget = element()
picker.selectionSummaryTarget = element()
picker.availabilityTargets = [element()]
picker.purchaseButtonTargets = Array.from({ length: 4 }, () => element())
picker.orderLabelTargets = [element(), element()]
picker.variantIdTarget = element()
picker.hasVariantIdTarget = true
picker.hasColorLabelTarget = false
picker.hasSavingsTarget = true
picker.hasSaleUntilTarget = false
picker.hasSizeGroupTarget = false
picker.hasSelectionSummaryTarget = true
picker.hasSizeSheetTarget = false
picker.hasSheetSizeButtonTarget = false
picker.sheetSizeButtonTargets = []
picker.dispatch = (_name, event) => { picker.lastVariant = event.detail.variant }
picker.variantIdTarget.value = "1"
picker.connect()
assert.equal(picker.variantIdTarget.value, 1, "Honor the SSR-selected variant id on connect")
assert.equal(picker.selectedColor, "Black")
assert.equal(picker.selectedSize, "S")
picker.variantIdTarget.value = ""
picker.connect()
assert.equal(picker.variantIdTarget.value, 2, "Start with an available variant when none is preset")
assert.ok(picker.purchaseButtonTargets.every((button) => !button.disabled))
assert.ok(picker.priceTargets.every((price) => price.textContent === "120 DH"), "Desktop and mobile prices agree")
assert.ok(picker.orderLabelTargets.every((label) => label.textContent === "Order — 120 DH"), "Order CTA includes the price")
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

// Size required: no size preselected; CTA reads "Choose my size" until a size is picked.
picker.variantsValue = [
  { id: 1, size: "S", color: "Gris chiné", stock: 2, price: "389 DH", price_cents: 38900 },
  { id: 2, size: "M", color: "Gris chiné", stock: 2, price: "389 DH", price_cents: 38900 }
]
picker.requireSizeValue = true
picker.compareAtValue = 44900
picker.compareAtDisplayValue = "449 DH"
picker.savingsDisplayValue = "60 DH"
picker.saleUntilWhenValue = ""
picker.variantIdTarget.value = ""
picker.sizeGroupTarget = element()
picker.hasSizeGroupTarget = true
picker.sizeSheetTarget = Object.assign(element(), {
  classList: {
    tokens: new Set(),
    add(name) { this.tokens.add(name) },
    remove(name) { this.tokens.delete(name) },
    contains(name) { return this.tokens.has(name) },
    toggle() {}
  },
  getAttribute() { return null },
  setAttribute() {}
})
picker.hasSizeSheetTarget = true
picker.hasSheetSizeButtonTarget = true
picker.sheetSizeButtonTargets = [element({ size: "S" }), element({ size: "M" })]
picker.sheetSizeButtonTargets.forEach((btn) => {
  btn.focus = () => {}
  btn.classList = { toggle() {}, add() {}, remove() {}, contains() { return false } }
})
let focused = false
picker.sizeButtonTargets[0].focus = () => { focused = true }
picker.connect()
assert.equal(picker.selectedSize, null, "Do not preselect a size when requireSize is on")
assert.equal(picker.variantIdTarget.value, "", "Variant id stays empty until a size is chosen")
assert.ok(picker.purchaseButtonTargets.every((button) => !button.disabled), "CTA stays tappable so it can open the size sheet")
assert.ok(picker.orderLabelTargets.every((label) => label.textContent === "Order — 389 DH"), "With size sheet, sticky stays Commander — price")
assert.equal(picker.selectionSummaryTarget.hidden, true, "Hide selection summary until a size is chosen")
assert.equal(picker.savingsTarget.hidden, false, "Show savings when there is no sale end")
assert.ok(picker.savingsTarget.textContent.includes("60 DH"))
const buyButton = Object.assign(element(), { name: "checkout", form: { requestSubmit(btn) { buyButton.submitted = btn === buyButton } }, getAttribute() { return null } })
let sizeBlocked = false
picker.ensureSize({ preventDefault() { sizeBlocked = true }, currentTarget: buyButton })
assert.ok(sizeBlocked, "First tap without a size is blocked")
assert.ok(picker.sizeSheetTarget.classList.contains("is-open"), "First tap opens the size sheet")
assert.equal(focused, false, "Sheet path does not scroll-focus on-page sizes")
picker.pickSizeAndContinue({ preventDefault() {}, currentTarget: { dataset: { size: "M" } } })
assert.equal(picker.variantIdTarget.value, 2)
assert.equal(buyButton.submitted, true, "Choosing a size in the sheet continues the pending buy")
assert.ok(!picker.sizeSheetTarget.classList.contains("is-open"), "Sheet closes after a size is picked")
assert.ok(picker.orderLabelTargets.every((label) => label.textContent === "Order — 389 DH"))
assert.equal(picker.selectionSummaryTarget.hidden, false)
assert.equal(picker.selectionSummaryTarget.textContent, "Gris chiné · Size M")
sizeBlocked = false
picker.ensureSize({ preventDefault() { sizeBlocked = true }, currentTarget: buyButton })
assert.equal(sizeBlocked, false, "With a size selected, ensureSize does not block")

// Fallback: without a sheet, first tap still focuses on-page sizes and CTA says choose-size.
picker.hasSizeSheetTarget = false
focused = false
picker.selectedSize = null
picker.render()
assert.ok(picker.orderLabelTargets.every((label) => label.textContent === "Choose my size"), "Without sheet, unset size uses choose-size CTA")
sizeBlocked = false
picker.ensureSize({ preventDefault() { sizeBlocked = true }, currentTarget: buyButton })
assert.ok(sizeBlocked)
assert.ok(focused, "Without a sheet, first tap focuses a size control")
picker.selectSize({ preventDefault() {}, currentTarget: { dataset: { size: "M" } } })

picker.hasSaleUntilTarget = true
picker.saleUntilWhenValue = "dimanche à 23 h 59"
picker.render()
assert.equal(picker.savingsTarget.hidden, true, "Hide savings when a sale deadline is set")
assert.equal(picker.saleUntilTarget.hidden, false)
assert.ok(picker.saleUntilTarget.textContent.includes("449 DH"))
assert.ok(picker.saleUntilTarget.textContent.includes("dimanche"))

picker.variantsValue = []
picker.requireSizeValue = false
picker.connect()
console.log("Variant selection: stock, mobile/desktop prices, comparison price, size gate, gallery event and submission checks passed")
