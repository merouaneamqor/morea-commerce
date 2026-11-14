// Run with: node script/variant_gallery_controller_smoke.mjs
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { chromium } from "playwright"

const pickerSrc = readFileSync(new URL("../app/javascript/controllers/variant_picker_controller.js", import.meta.url), "utf8")
  .replace(/^import .*$/m, "")
  .replace("export default class extends Controller", "class VariantPicker extends Controller")
const gallerySrc = readFileSync(new URL("../app/javascript/controllers/variant_gallery_controller.js", import.meta.url), "utf8")
  .replace(/^import .*$/m, "")
  .replace("export default class extends Controller", "class VariantGallery extends Controller")

const variants = [
  { id: 1, size: "S", color: "Black", stock: 2, price: "100 MAD", price_cents: 10000, images: ["https://cdn.test/black-1.jpg", "https://cdn.test/black-2.jpg"] },
  { id: 2, size: "S", color: "Pink", stock: 2, price: "100 MAD", price_cents: 10000, images: ["https://cdn.test/pink-1.jpg"] },
  { id: 3, size: "S", color: "White", stock: 2, price: "100 MAD", price_cents: 10000, images: null }
]
const productImages = ["https://cdn.test/product-1.jpg", "https://cdn.test/product-2.jpg"]

function pageHtml({ registerOrder = "together", initialVariantId = 1, ssrImages = productImages } = {}) {
  const ssrShots = ssrImages.map((src, index) =>
    `<div class="pdp__shot${index === 0 ? " pdp__shot--lead" : ""}"><img src="${src}" alt="shot"></div>`
  ).join("")

  const register = registerOrder === "picker-first"
    ? `app.register("variant-picker", VariantPicker)
       await new Promise((r) => setTimeout(r, 30))
       app.register("variant-gallery", VariantGallery)`
    : registerOrder === "gallery-first"
      ? `app.register("variant-gallery", VariantGallery)
         await new Promise((r) => setTimeout(r, 30))
         app.register("variant-picker", VariantPicker)`
      : `app.register("variant-picker", VariantPicker)
         app.register("variant-gallery", VariantGallery)`

  return `<!doctype html>
<html><body>
<div id="root"
  data-controller="variant-gallery variant-picker"
  data-action="variant-picker:change->variant-gallery#show"
  data-variant-gallery-product-images-value='${JSON.stringify(productImages)}'
  data-variant-picker-variants-value='${JSON.stringify(variants)}'
  data-variant-picker-track-inventory-value="false"
  data-variant-picker-available-label-value="Available"
  data-variant-picker-unavailable-label-value="Sold out"
  data-variant-picker-order-label-value="Order"
  data-variant-picker-compare-at-value="0">
  <div class="pdp__gallery" data-variant-gallery-target="gallery">${ssrShots}</div>
  <template data-variant-gallery-target="shotTemplate">
    <div class="pdp__shot"><img alt="x" class="h-full w-full object-cover"></div>
  </template>
  <input data-variant-picker-target="variantId" value="${initialVariantId}">
  <button data-variant-picker-target="colorButton" data-color="Black" data-action="variant-picker#selectColor">Black</button>
  <button data-variant-picker-target="colorButton" data-color="Pink" data-action="variant-picker#selectColor">Pink</button>
  <button data-variant-picker-target="colorButton" data-color="White" data-action="variant-picker#selectColor">White</button>
  <button data-variant-picker-target="sizeButton" data-size="S" data-action="variant-picker#selectSize">S</button>
  <span data-variant-picker-target="price"></span>
  <span data-variant-picker-target="availability"></span>
  <button data-variant-picker-target="purchaseButton"></button>
  <span data-variant-picker-target="orderLabel"></span>
</div>
<script type="module">
import { Application, Controller } from "https://unpkg.com/@hotwired/stimulus@3.2.2/dist/stimulus.js"
${pickerSrc}
${gallerySrc}
const app = Application.start()
${register}
window.__errors = []
window.addEventListener("error", (e) => window.__errors.push(String(e.message)))
window.__ready = true
</script>
</body></html>`
}

const browser = await chromium.launch({ headless: true, args: ["--no-sandbox"] })

async function runCase(name, options, actions) {
  const page = await browser.newPage()
  const errors = []
  page.on("pageerror", (err) => errors.push(err.message))
  await page.setContent(pageHtml(options), { waitUntil: "networkidle" })
  await page.waitForFunction(() => window.__ready === true)
  await page.waitForTimeout(80)
  const shots = async () => page.$$eval(".pdp__gallery img", (imgs) => imgs.map((img) => img.getAttribute("src")))
  await actions({ page, shots })
  const pageErrors = await page.evaluate(() => window.__errors)
  assert.deepEqual([...errors, ...pageErrors], [], `${name}: console errors`)
  await page.close()
  console.log(`ok - ${name}`)
}

await runCase("first load uses selected variant photos", { registerOrder: "together", ssrImages: productImages }, async ({ shots }) => {
  assert.deepEqual(await shots(), variants[0].images)
})

await runCase("lazy picker-first still syncs on gallery connect", { registerOrder: "picker-first", ssrImages: productImages }, async ({ shots }) => {
  assert.deepEqual(await shots(), variants[0].images)
})

await runCase("lazy gallery-first receives picker connect change", { registerOrder: "gallery-first", ssrImages: productImages }, async ({ shots }) => {
  assert.deepEqual(await shots(), variants[0].images)
})

await runCase("switching colors and back", { registerOrder: "together" }, async ({ page, shots }) => {
  await page.click('button[data-color="Pink"]')
  assert.deepEqual(await shots(), variants[1].images)
  await page.click('button[data-color="Black"]')
  assert.deepEqual(await shots(), variants[0].images)
  await page.click('button[data-color="White"]')
  assert.deepEqual(await shots(), productImages)
  await page.click('button[data-color="Pink"]')
  assert.deepEqual(await shots(), variants[1].images)
})

await runCase("mobile viewport color change", { registerOrder: "together" }, async ({ page, shots }) => {
  await page.setViewportSize({ width: 390, height: 844 })
  await page.click('button[data-color="Pink"]')
  assert.deepEqual(await shots(), variants[1].images)
  await page.click('button[data-color="White"]')
  assert.deepEqual(await shots(), productImages)
})

await browser.close()
console.log("Variant gallery: first load, lazy controller order, color switch/back, missing-image fallback and mobile checks passed")
