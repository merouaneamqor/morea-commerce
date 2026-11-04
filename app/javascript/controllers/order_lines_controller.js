import { Controller } from "@hotwired/stimulus"

// Search products and manage line items on the admin order form
export default class extends Controller {
  static targets = ["query", "results", "list", "empty", "template", "total", "picker", "submit"]
  static values = {
    searchUrl: String,
    quickUrl: String,
    currency: { type: String, default: "DH" }
  }

  connect() {
    this.index = this.listTarget.querySelectorAll("[data-order-line]").length
    this.refreshEmpty()
    this.recalc()
  }

  disconnect() {
    clearTimeout(this.timer)
    this.controller?.abort()
  }

  // An empty field lists the first products; typing narrows by name, SKU or variant (accents ignored by the server).
  search() {
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.fetchResults(), 150)
  }

  async fetchResults() {
    const q = this.queryTarget.value.trim()
    this.controller?.abort()
    this.controller = new AbortController()

    const url = new URL(this.searchUrlValue, window.location.origin)
    url.searchParams.set("q", q)
    let items
    try {
      const res = await fetch(url, { headers: { Accept: "application/json" }, credentials: "same-origin", signal: this.controller.signal })
      if (!res.ok) throw new Error(String(res.status))
      items = await res.json()
    } catch (error) {
      if (error.name === "AbortError") return
      this.showMessage("Search is unavailable right now. Try again.")
      return
    }

    this.resultsTarget.innerHTML = ""
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
    if (!items.length) this.resultsTarget.insertAdjacentHTML("beforeend", `<p class="px-3 py-2 text-[13px] text-[#616161]" data-no-products>No products found</p>`)
    this.resultsTarget.appendChild(this.createButton(q))
    this.resultsTarget.hidden = false
  }

  createButton(name) {
    const btn = document.createElement("button")
    btn.type = "button"
    btn.dataset.createProduct = ""
    btn.className = "flex w-full items-center gap-2 border-t border-[#ebebeb] px-3 py-2 text-start text-[13px] font-semibold text-[#a8432e] hover:bg-[#f7f7f7]"
    btn.textContent = "+ Créer le produit"
    btn.addEventListener("click", () => this.showCreateForm(name))
    return btn
  }

  showCreateForm(name) {
    this.resultsTarget.innerHTML = `
      <form class="space-y-2 p-3" data-create-form>
        <input name="name" value="${this.escape(name)}" placeholder="Product name" required class="admin-input" data-create-name>
        <input name="price" type="number" min="1" step="0.01" placeholder="Price (${this.escape(this.currencyValue)})" required class="admin-input" data-create-price>
        <p class="text-[13px] text-[#8e0b21]" data-create-error hidden></p>
        <div class="flex justify-end gap-2">
          <button type="button" class="admin-btn-secondary" data-create-cancel>Cancel</button>
          <button type="submit" class="admin-btn">Créer</button>
        </div>
      </form>`
    const form = this.resultsTarget.querySelector("[data-create-form]")
    form.addEventListener("submit", (event) => this.createProduct(event, form))
    form.querySelector("[data-create-cancel]").addEventListener("click", () => this.fetchResults())
    form.querySelector("[data-create-price]").focus()
  }

  async createProduct(event, form) {
    event.preventDefault()
    const error = form.querySelector("[data-create-error]")
    const token = document.querySelector("meta[name=csrf-token]")?.content
    const body = new URLSearchParams({ name: form.name.value, price: form.price.value })
    const res = await fetch(this.quickUrlValue, {
      method: "POST",
      credentials: "same-origin",
      headers: { Accept: "application/json", "X-CSRF-Token": token || "" },
      body
    })
    const data = await res.json().catch(() => ({}))
    if (!res.ok) {
      error.textContent = data.error || "Could not create the product."
      error.hidden = false
      return
    }
    this.add(data)
  }

  showMessage(text) {
    this.resultsTarget.innerHTML = `<p class="px-3 py-2 text-[13px] text-[#616161]">${this.escape(text)}</p>`
    this.resultsTarget.hidden = false
  }

  closeOutside(event) {
    if (this.hasPickerTarget && !this.pickerTarget.contains(event.target)) this.resultsTarget.hidden = true
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
    // No product, or products worth 0: nothing to save (the server refuses it too).
    if (this.hasSubmitTarget) this.submitTarget.disabled = subtotal <= 0
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
