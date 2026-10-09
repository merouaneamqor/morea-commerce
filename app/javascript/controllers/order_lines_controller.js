import { Controller } from "@hotwired/stimulus"

// Search products and manage line items on the admin order form
export default class extends Controller {
  static targets = ["query", "results", "list", "empty", "template", "total"]
  static values = {
    searchUrl: String,
    currency: { type: String, default: "DH" }
  }

  connect() {
    this.index = this.listTarget.querySelectorAll("[data-order-line]").length
    this.refreshEmpty()
    this.recalc()
  }

  async search() {
    const q = this.queryTarget.value.trim()
    if (q.length < 1) {
      this.resultsTarget.innerHTML = ""
      this.resultsTarget.hidden = true
      return
    }

    const url = new URL(this.searchUrlValue, window.location.origin)
    url.searchParams.set("q", q)
    const res = await fetch(url, { headers: { Accept: "application/json" } })
    const items = await res.json()
    this.resultsTarget.innerHTML = ""
    if (!items.length) {
      this.resultsTarget.innerHTML = `<p class="px-3 py-2 text-[13px] text-[#616161]">No products found</p>`
      this.resultsTarget.hidden = false
      return
    }

    items.forEach((item) => {
      const btn = document.createElement("button")
      btn.type = "button"
      btn.className = "flex w-full items-center gap-3 px-3 py-2 text-start text-[13px] hover:bg-[#f7f7f7]"
      btn.innerHTML = `
        <span class="min-w-0 flex-1 truncate font-medium">${this.escape(item.label)}</span>
        <span class="tabular-nums text-[#616161]">${this.escape(item.price_display)}</span>
      `
      btn.addEventListener("click", () => this.add(item))
      this.resultsTarget.appendChild(btn)
    })
    this.resultsTarget.hidden = false
  }

  add(item) {
    const existing = this.listTarget.querySelector(
      `[data-order-line][data-product-id="${item.product_id}"][data-variant-id="${item.product_variant_id || ""}"]`
    )
    if (existing) {
      const qty = existing.querySelector("[data-qty]")
      qty.value = String(parseInt(qty.value, 10) + 1)
      this.recalc()
      this.clearSearch()
      return
    }

    const html = this.templateTarget.innerHTML
      .replaceAll("__INDEX__", String(this.index))
      .replaceAll("__PRODUCT_ID__", String(item.product_id))
      .replaceAll("__VARIANT_ID__", item.product_variant_id ? String(item.product_variant_id) : "")
      .replaceAll("__LABEL__", this.escape(item.label))
      .replaceAll("__PRICE__", String(item.price_cents))
      .replaceAll("__PRICE_DISPLAY__", this.escape(item.price_display))
      .replaceAll("__QTY__", "1")

    this.listTarget.insertAdjacentHTML("beforeend", html)
    this.index += 1
    this.refreshEmpty()
    this.recalc()
    this.clearSearch()
  }

  remove(event) {
    event.currentTarget.closest("[data-order-line]")?.remove()
    this.refreshEmpty()
    this.recalc()
  }

  recalc() {
    let subtotal = 0
    this.listTarget.querySelectorAll("[data-order-line]").forEach((row) => {
      const price = parseInt(row.dataset.priceCents, 10) || 0
      const qty = parseInt(row.querySelector("[data-qty]")?.value, 10) || 0
      subtotal += price * qty
      const lineTotal = row.querySelector("[data-line-total]")
      if (lineTotal) lineTotal.textContent = this.formatMoney(price * qty)
    })
    if (this.hasTotalTarget) {
      this.totalTarget.textContent = this.formatMoney(subtotal)
    }
  }

  clearSearch() {
    this.queryTarget.value = ""
    this.resultsTarget.innerHTML = ""
    this.resultsTarget.hidden = true
  }

  refreshEmpty() {
    if (!this.hasEmptyTarget) return
    this.emptyTarget.hidden = this.listTarget.querySelectorAll("[data-order-line]").length > 0
  }

  formatMoney(cents) {
    return `${Math.round(cents / 100).toLocaleString("en-MA")} ${this.currencyValue}`
  }

  escape(value) {
    return String(value ?? "")
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
  }
}
