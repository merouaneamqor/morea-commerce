import { Controller } from "@hotwired/stimulus"

// Size / color picker that resolves a product_variant_id
export default class extends Controller {
  static targets = ["variantId", "sizeButton", "colorButton", "colorLabel"]
  static values = {
    variants: Array
  }

  connect() {
    this.selectedSize = this.firstAvailableSize()
    this.selectedColor = this.firstAvailableColor(this.selectedSize)
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
      btn.classList.toggle("is-active", btn.dataset.size === this.selectedSize)
    })

    this.colorButtonTargets.forEach((btn) => {
      const available = this.colorsFor(this.selectedSize).includes(btn.dataset.color)
      btn.classList.toggle("is-active", btn.dataset.color === this.selectedColor)
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
  }

  firstAvailableSize() {
    const sizes = [...new Set(this.variantsValue.map((v) => v.size).filter(Boolean))]
    return sizes[0] || null
  }

  firstAvailableColor(size) {
    const colors = this.colorsFor(size)
    return colors[0] || null
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
