import { Controller } from "@hotwired/stimulus"

// Size / color picker that resolves a product_variant_id
export default class extends Controller {
  static targets = ["variantId", "sizeButton", "colorButton", "colorLabel", "availability", "purchaseButton", "orderLabel", "price", "comparePrice"]
  static values = {
    variants: Array,
    trackInventory: Boolean,
    availableLabel: String,
    unavailableLabel: String,
    orderLabel: String,
    compareAt: Number
  }

  connect() {
    if (!this.variantsValue.length) return
    const initial = this.variantsValue.find((variant) => this.inStock(variant)) || this.variantsValue[0]
    this.selectedSize = initial.size
    this.selectedColor = initial.color
    this.render()
  }

  selectSize(event) {
    event.preventDefault()
    this.selectedSize = event.currentTarget.dataset.size
    const colors = this.colorsFor(this.selectedSize)
    if (!colors.includes(this.selectedColor)) {
      this.selectedColor = colors[0] || null
    }
    this.render()
  }

  selectColor(event) {
    event.preventDefault()
    this.selectedColor = event.currentTarget.dataset.color
    this.render()
  }

  render() {
    this.sizeButtonTargets.forEach((btn) => {
      const available = this.variantsValue.some((variant) => variant.size === btn.dataset.size && this.inStock(variant))
      btn.classList.toggle("is-unavailable", !available)
      btn.classList.toggle("is-active", btn.dataset.size === this.selectedSize)
      btn.setAttribute("aria-pressed", String(btn.dataset.size === this.selectedSize))
    })

    this.colorButtonTargets.forEach((btn) => {
      const available = this.colorsFor(this.selectedSize).includes(btn.dataset.color)
      btn.classList.toggle("is-active", btn.dataset.color === this.selectedColor)
      btn.setAttribute("aria-pressed", String(btn.dataset.color === this.selectedColor))
      btn.classList.toggle("is-unavailable", !this.variantsValue.some((variant) =>
        (!this.selectedSize || variant.size === this.selectedSize) && variant.color === btn.dataset.color && this.inStock(variant)
      ))
      btn.hidden = !available
    })

    if (this.hasColorLabelTarget) {
      this.colorLabelTarget.textContent = this.selectedColor || "—"
    }

    const match = this.variantsValue.find((v) => {
      const sizeOk = !this.selectedSize || v.size === this.selectedSize
      const colorOk = !this.selectedColor || v.color === this.selectedColor
      return sizeOk && colorOk
    })

    if (this.hasVariantIdTarget) {
      this.variantIdTarget.value = match ? match.id : ""
    }

    this.purchasable = !!match && this.inStock(match)
    this.availabilityTargets.forEach((label) => {
      label.textContent = this.purchasable ? this.availableLabelValue : this.unavailableLabelValue
    })
    this.purchaseButtonTargets.forEach((button) => { button.disabled = !this.purchasable })
    this.orderLabelTargets.forEach((label) => {
      label.textContent = this.purchasable ? this.orderLabelValue : this.unavailableLabelValue
    })
    if (match) {
      this.priceTargets.forEach((label) => { label.textContent = match.price })
      this.comparePriceTargets.forEach((label) => { label.hidden = this.compareAtValue <= match.price_cents })
    }

    this.dispatch("change", { detail: { variant: match || null } })
  }

  inStock(variant) {
    return !this.trackInventoryValue || variant.stock > 0
  }

  validate(event) {
    if (this.variantsValue.length && !this.purchasable) event.preventDefault()
  }

  colorsFor(size) {
    return [...new Set(
      this.variantsValue
        .filter((v) => !size || v.size === size)
        .map((v) => v.color)
        .filter(Boolean)
    )]
  }
}
