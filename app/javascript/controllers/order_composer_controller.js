import OrderLinesController from "controllers/order_lines_controller"

// The new-order window. The products part works in two steps, like the delivery apps do: pick a product (and its variant),
// see its price, choose a quantity, then "Ajouter un produit à la commande" puts it on the order. The lines, the search,
// "Produit non listé ?" and the totals come from OrderLinesController; this adds the pick step and the fees.
export default class extends OrderLinesController {
  static targets = [...OrderLinesController.targets, "variant", "quantity", "price", "addButton", "excluded", "shippingField", "shippingInput", "advance", "advanceText"]

  connect() {
    super.connect()
    this.group = null
    this.selected = null
    this.refreshPick()
  }

  // Search results are one row per product; the variants of a product are chosen in the Variante list.
  renderResults(items, q) {
    const groups = new Map()
    items.forEach((item) => {
      if (!groups.has(item.product_id)) groups.set(item.product_id, { productId: item.product_id, name: item.label.split(" — ")[0], items: [] })
      groups.get(item.product_id).items.push(item)
    })

    this.resultsTarget.innerHTML = ""
    groups.forEach((group) => {
      const prices = group.items.map((item) => item.price_cents)
      const from = Math.min(...prices)
      const btn = document.createElement("button")
      btn.type = "button"
      btn.className = "flex w-full items-center gap-3 px-3 py-2 text-start text-[13px] hover:bg-[#f7f7f7]"
      btn.innerHTML = `
        <span class="min-w-0 flex-1 truncate font-medium">${this.escape(group.name)}</span>
        <span class="tabular-nums text-[#616161]">${group.items.length > 1 ? `${group.items.length} ✕ ` : ""}${this.escape(group.items.find((item) => item.price_cents === from).price_display)}</span>
      `
      btn.addEventListener("click", () => this.pick(group))
      this.resultsTarget.appendChild(btn)
    })
    if (!groups.size) this.resultsTarget.insertAdjacentHTML("beforeend", `<p class="px-3 py-2 text-[13px] text-[#616161]" data-no-products>—</p>`)
    this.resultsTarget.appendChild(this.createButton(q))
    this.resultsTarget.hidden = false
  }

  pick(group) {
    this.group = group
    this.selected = null
    this.queryTarget.value = group.name
    this.resultsTarget.hidden = true

    const variants = group.items.filter((item) => item.product_variant_id)
    const select = this.variantTarget
    select.innerHTML = ""
    if (variants.length) {
      select.add(new Option(select.dataset.placeholder || "—", ""))
      variants.forEach((item) => select.add(new Option(item.label.split(" — ").slice(1).join(" — ") || item.label, String(item.product_variant_id))))
      select.disabled = false
      this.priceTarget.value = ""
      this.priceTarget.placeholder = this.priceTarget.dataset.placeholderVariant
    } else {
      select.add(new Option("—", ""))
      select.disabled = true
      this.selected = group.items[0]
      this.priceTarget.value = this.selected.price_display
    }
    this.refreshPick()
  }

  variantChanged() {
    const id = this.variantTarget.value
    this.selected = this.group?.items.find((item) => String(item.product_variant_id) === id) || null
    this.priceTarget.value = this.selected ? this.selected.price_display : ""
    this.refreshPick()
  }

  addPending() {
    if (!this.selected) return
    this.add(this.selected, Math.max(parseInt(this.quantityTarget.value, 10) || 1, 1))
    this.group = null
    this.selected = null
    this.variantTarget.innerHTML = ""
    this.variantTarget.disabled = true
    this.priceTarget.value = ""
    this.priceTarget.placeholder = this.priceTarget.dataset.placeholderProduct
    this.quantityTarget.value = "1"
    this.refreshPick()
  }

  // "Produit non listé ?" and the quick form of the parent put the new product straight on the order.
  refreshPick() {
    const ready = !!this.selected
    this.quantityTarget.disabled = !ready
    this.addButtonTarget.disabled = !ready
  }

  clearSearch() {
    super.clearSearch()
    this.group = null
    this.selected = null
    if (this.hasVariantTarget) { this.variantTarget.innerHTML = ""; this.variantTarget.disabled = true }
    if (this.hasPriceTarget) { this.priceTarget.value = ""; this.priceTarget.placeholder = this.priceTarget.dataset.placeholderProduct }
    if (this.hasQuantityTarget) this.refreshPick()
  }

  // "Exclus": the customer pays the products only, so the delivery fee is left out (a disabled field is not sent).
  toggleShipping() {
    const excluded = this.excludedTarget.checked
    this.shippingFieldTarget.hidden = excluded
    this.shippingInputTarget.disabled = excluded
    this.recalc()
  }

  // What the order adds up to, as the person types. A preview only: the server computes the saved total.
  showTotals(subtotal) {
    if (!this.hasGrandTotalTarget) return
    const cents = (input) => Math.max(Math.round((parseFloat(input?.value) || 0) * 100), 0)
    const excluded = this.hasExcludedTarget && this.excludedTarget.checked
    const shipping = excluded ? 0 : cents(this.hasShippingInputTarget ? this.shippingInputTarget : null)
    const total = subtotal + shipping
    const advance = Math.min(cents(this.hasAdvanceTarget ? this.advanceTarget : null), total)
    if (this.hasSubtotalTarget) this.subtotalTarget.textContent = this.formatMoney(subtotal)
    if (this.hasShippingTextTarget) this.shippingTextTarget.textContent = this.formatMoney(shipping)
    this.grandTotalTarget.textContent = this.formatMoney(total)
    if (this.hasAdvanceTextTarget) this.advanceTextTarget.textContent = advance > 0 ? `-${this.formatMoney(advance)}` : this.formatMoney(0)
    if (this.hasToCollectTarget) this.toCollectTarget.textContent = this.formatMoney(total - advance)
  }
}
