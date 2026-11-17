// Run with: node script/checkout_city_test.mjs
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import vm from "node:vm"

const source = readFileSync(new URL("../app/javascript/controllers/checkout_city_controller.js", import.meta.url), "utf8")
const CheckoutCity = vm.runInNewContext(
  source.replace(/^import .*$/m, "class Controller {}")
    .replace("export default class", "class CheckoutCity") + "\nCheckoutCity"
)

function checkout(values = {}) {
  const controller = new CheckoutCity()
  Object.assign(controller, {
    citiesValue: [],
    ratesValue: {},
    subtotalValue: 10_000,
    discountValue: 0,
    freeThresholdValue: 0,
    fallbackShippingValue: 3_000,
    currencyValue: "MAD",
    localeValue: "en-MA",
    freeLabelValue: "Free delivery",
    pendingLabelValue: "Choose your city",
    confirmTemplateValue: "Confirm my order · %{total}",
    hasCityTarget: true,
    cityTarget: { value: "" },
    ...values
  })
  for (const name of ["shipping", "shippingInput", "total", "mobileTotal", "bagPreview", "submitLabel", "stickyLabel"]) {
    controller[`has${name[0].toUpperCase()}${name.slice(1)}Target`] = true
    controller[`${name}Target`] = { textContent: "", value: "" }
  }
  return controller
}

function expectTotals(controller, { shipping, total, shippingInput }) {
  controller.refreshTotals()
  assert.equal(controller.shippingTarget.textContent, shipping, "Show the current shipping charge")
  for (const name of ["total", "mobileTotal", "bagPreview"]) {
    assert.equal(controller[`${name}Target`].textContent, total, `${name} must show the same payable total`)
  }
  for (const name of ["submitLabel", "stickyLabel"]) {
    assert.equal(controller[`${name}Target`].textContent, `Confirm my order · ${total}`, `${name} must include the payable total`)
  }
  if (shippingInput != null) assert.equal(controller.shippingInputTarget.value, shippingInput)
}

// A merchant without carrier city data still charges their configured flat fee.
const flat = checkout()
expectTotals(flat, { shipping: "30 MAD", total: "130 MAD", shippingInput: "30" })
flat.cityTarget.value = "  Small village  "
assert.equal(flat.cityValue(), "Small village", "Accept free-text destinations when no carrier city list exists")
expectTotals(flat, { shipping: "30 MAD", total: "130 MAD", shippingInput: "30" })
let prevented = false
flat.validateCity({ preventDefault() { prevented = true } })
assert.equal(prevented, false, "Do not require selecting a carrier city when none are configured")

const carrier = checkout({ citiesValue: ["Casablanca", "Rabat"], ratesValue: { Casablanca: 1_900, Rabat: 0 } })
expectTotals(carrier, { shipping: "Choose your city", total: "100 MAD" })
carrier.cityTarget.value = " casablanca "
assert.equal(carrier.cityValue(), "Casablanca", "Resolve case and whitespace to the carrier city name")
expectTotals(carrier, { shipping: "19 MAD", total: "119 MAD", shippingInput: "19" })
carrier.cityTarget.value = "Rabat"
expectTotals(carrier, { shipping: "Free delivery", total: "100 MAD", shippingInput: "0" })
carrier.cityTarget.value = "Unknown destination"
assert.equal(carrier.cityValue(), "", "Do not silently accept unsupported carrier destinations")
expectTotals(carrier, { shipping: "Choose your city", total: "100 MAD" })

const free = checkout({ subtotalValue: 15_000, freeThresholdValue: 15_000 })
expectTotals(free, { shipping: "Free delivery", total: "150 MAD", shippingInput: "0" })
free.discountValue = 1_000
expectTotals(free, { shipping: "30 MAD", total: "170 MAD", shippingInput: "30" })
free.discountValue = 20_000
expectTotals(free, { shipping: "30 MAD", total: "30 MAD", shippingInput: "30" })

const freeCarrier = checkout({
  citiesValue: ["Casablanca"],
  ratesValue: { Casablanca: 1_900 },
  cityTarget: { value: "Casablanca" },
  freeThresholdValue: 10_000
})
expectTotals(freeCarrier, { shipping: "Free delivery", total: "100 MAD", shippingInput: "0" })

const missingRate = checkout({ citiesValue: ["Rabat"], cityTarget: { value: "Rabat" } })
expectTotals(missingRate, { shipping: "30 MAD", total: "130 MAD", shippingInput: "30" })

console.log("Checkout city and total checks passed: flat shipping, free-text cities, carrier rates, pending cities, free delivery thresholds, discounts, and matching totals/CTA labels.")
