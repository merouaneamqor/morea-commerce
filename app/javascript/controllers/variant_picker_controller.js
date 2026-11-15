import { Controller } from "@hotwired/stimulus"

// Size / color picker that resolves a product_variant_id
export default class extends Controller {
  static targets = [
    "variantId", "sizeButton", "colorButton", "colorLabel", "availability",
    "purchaseButton", "orderLabel", "price", "comparePrice", "savings", "saleUntil",
    "sizeGroup", "selectionSummary", "sizeSheet", "sizeSheetPanel", "sheetSizeButton"
  ]
  static values = {
    variants: Array,
    trackInventory: Boolean,
    requireSize: { type: Boolean, default: false },
    availableLabel: String,
    unavailableLabel: String,
    orderLabel: String,
    orderWithPriceLabel: String,
    chooseSizeLabel: String,
    selectionSummaryLabel: String,
    selectionSummarySizeLabel: String,
    compareAt: Number,
    compareAtDisplay: String,
    saveAmountLabel: String,
    priceRevertsLabel: String,
    saleUntilWhen: String,
    savingsDisplay: String
  }

  connect() {
    if (!this.variantsValue.length) return
    const presetId = this.hasVariantIdTarget ? this.variantIdTarget.value : ""
    const preset = presetId
      ? this.variantsValue.find((variant) => String(variant.id) === String(presetId))
      : null
    const initial = preset || this.variantsValue.find((variant) => this.inStock(variant)) || this.variantsValue[0]
    this.selectedColor = initial.color
    // Never preselect a size when sizes exist — sticky used to submit the default (often S).
    if (this.requireSizeValue && this.sizeButtonTargets.length) {
      this.selectedSize = null
    } else {
      this.selectedSize = initial.size
    }
    this.boundKeydown = this.onSheetKeydown.bind(this)
    this.render()
  }

  disconnect() {
    this.unlockScroll()
    document.removeEventListener("keydown", this.boundKeydown)
  }

  selectSize(event) {
    event.preventDefault()
    this.applySize(event.currentTarget.dataset.size)
  }

  pickSizeAndContinue(event) {
    event.preventDefault()
    this.applySize(event.currentTarget.dataset.size)
    this.closeSizeSheet()
    this.continuePendingPurchase()
  }

  applySize(size) {
    this.selectedSize = size
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

  ensureSize(event) {
    if (!this.needsSize()) return
    event.preventDefault()
    this.pendingPurchaseButton = event.currentTarget
    if (this.hasSizeSheetTarget) {
      this.openSizeSheet()
      return
    }
    this.focusSizes()
  }

  openSizeSheet() {
    if (!this.hasSizeSheetTarget) return
    this.sizeSheetTarget.classList.add("is-open")
    this.sizeSheetTarget.setAttribute("aria-hidden", "false")
    this.lockScroll()
    document.addEventListener("keydown", this.boundKeydown)
    requestAnimationFrame(() => {
      const first = this.sheetSizeButtonTargets.find((btn) => !btn.classList.contains("is-unavailable"))
        || this.sheetSizeButtonTargets[0]
      first?.focus({ preventScroll: true })
    })
  }

  closeSizeSheet(event) {
    if (event) event.preventDefault()
    if (!this.hasSizeSheetTarget) return
    this.sizeSheetTarget.classList.remove("is-open")
    this.sizeSheetTarget.setAttribute("aria-hidden", "true")
    this.unlockScroll()
    document.removeEventListener("keydown", this.boundKeydown)
  }

  onSheetKeydown(event) {
    if (event.key !== "Escape") return
    this.closeSizeSheet()
  }

  continuePendingPurchase() {
    const button = this.pendingPurchaseButton
    this.pendingPurchaseButton = null
    if (!button || this.needsSize() || !this.purchasable) return

    const form = button.form || (button.getAttribute("form") && document.getElementById(button.getAttribute("form")))
    if (form && typeof form.requestSubmit === "function") {
      form.requestSubmit(button)
      return
    }
    button.click()
  }

  lockScroll() {
    document.documentElement.classList.add("size-sheet-open")
  }

  unlockScroll() {
    document.documentElement.classList.remove("size-sheet-open")
  }

  render() {
    this.sizeButtonTargets.forEach((btn) => {
      const available = this.variantsValue.some((variant) => variant.size === btn.dataset.size && this.inStock(variant))
      btn.classList.toggle("is-unavailable", !available)
      btn.classList.toggle("is-active", !!this.selectedSize && btn.dataset.size === this.selectedSize)
      btn.setAttribute("aria-pressed", String(!!this.selectedSize && btn.dataset.size === this.selectedSize))
    })

    if (this.hasSheetSizeButtonTarget) {
      this.sheetSizeButtonTargets.forEach((btn) => {
        const available = this.variantsValue.some((variant) => variant.size === btn.dataset.size && this.inStock(variant))
        btn.classList.toggle("is-unavailable", !available)
        btn.classList.toggle("is-active", !!this.selectedSize && btn.dataset.size === this.selectedSize)
        btn.setAttribute("aria-pressed", String(!!this.selectedSize && btn.dataset.size === this.selectedSize))
        btn.disabled = !available
      })
    }

    this.colorButtonTargets.forEach((btn) => {
      const available = this.colorsFor(this.selectedSize).includes(btn.dataset.color)
      btn.classList.toggle("is-active", btn.dataset.color === this.selectedColor)
      btn.setAttribute("aria-pressed", String(btn.dataset.color === this.selectedColor))
      btn.classList.toggle("is-unavailable", !this.variantsValue.some((variant) =>
        (!this.selectedSize || variant.size === this.selectedSize) && variant.color === btn.dataset.color && this.inStock(variant)
      ))
      btn.hidden = this.selectedSize ? !available : false
    })

    if (this.hasColorLabelTarget) {
      this.colorLabelTarget.textContent = this.selectedColor || "—"
    }

    const waitingForSize = this.needsSize()
    const match = waitingForSize
      ? null
      : this.variantsValue.find((v) => {
        const sizeOk = !this.selectedSize || v.size === this.selectedSize
        const colorOk = !this.selectedColor || v.color === this.selectedColor
        return sizeOk && colorOk
      })

    const preview = match || this.previewVariant()

    if (this.hasVariantIdTarget) {
      this.variantIdTarget.value = match ? match.id : ""
    }

    this.purchasable = !!match && this.inStock(match)
    this.availabilityTargets.forEach((label) => {
      label.textContent = (this.purchasable || waitingForSize)
        ? this.availableLabelValue
        : this.unavailableLabelValue
    })

    // Keep the CTA tappable when size is missing so the first tap can open the size sheet.
    this.purchaseButtonTargets.forEach((button) => {
      button.disabled = waitingForSize ? false : !this.purchasable
    })

    const priceText = preview?.price || ""
    this.orderLabelTargets.forEach((label) => {
      if (waitingForSize) {
        label.textContent = this.chooseSizeLabelValue || this.orderLabelValue
      } else if (!this.purchasable) {
        label.textContent = this.unavailableLabelValue
      } else {
        label.textContent = this.orderLabelFor(priceText)
      }
    })

    this.updateSelectionSummary()

    if (preview) {
      this.priceTargets.forEach((label) => { label.textContent = preview.price })
      this.comparePriceTargets.forEach((label) => {
        label.hidden = this.compareAtValue <= preview.price_cents
      })
      this.updateOfferCopy(preview.price_cents)
    }

    this.dispatch("change", { detail: { variant: preview || null } })
  }

  orderLabelFor(priceText) {
    const template = this.orderWithPriceLabelValue
    if (template && priceText) return template.replace("%{price}", priceText)
    return this.orderLabelValue
  }

  updateSelectionSummary() {
    if (!this.hasSelectionSummaryTarget) return
    if (!this.selectedSize) {
      this.selectionSummaryTarget.hidden = true
      this.selectionSummaryTarget.textContent = ""
      return
    }

    let text = ""
    if (this.selectedColor && this.selectionSummaryLabelValue) {
      text = this.selectionSummaryLabelValue
        .replace("%{color}", this.selectedColor)
        .replace("%{size}", this.selectedSize)
    } else if (this.selectionSummarySizeLabelValue) {
      text = this.selectionSummarySizeLabelValue.replace("%{size}", this.selectedSize)
    } else {
      text = this.selectedSize
    }
    this.selectionSummaryTarget.textContent = text
    this.selectionSummaryTarget.hidden = false
  }

  updateOfferCopy(priceCents) {
    const onSale = this.compareAtValue > priceCents
    const untilWhen = this.saleUntilWhenValue
    if (this.hasSaleUntilTarget) {
      if (onSale && untilWhen && this.priceRevertsLabelValue && this.compareAtDisplayValue) {
        this.saleUntilTarget.hidden = false
        this.saleUntilTarget.textContent = this.priceRevertsLabelValue
          .replace("%{when}", untilWhen)
          .replace("%{compare}", this.compareAtDisplayValue)
      } else {
        this.saleUntilTarget.hidden = true
      }
    }
    if (this.hasSavingsTarget) {
      const showSave = onSale && !untilWhen
      this.savingsTarget.hidden = !showSave
      if (showSave && this.saveAmountLabelValue && this.savingsDisplayValue) {
        this.savingsTarget.textContent = this.saveAmountLabelValue.replace("%{amount}", this.savingsDisplayValue)
      }
    }
  }

  previewVariant() {
    return this.variantsValue.find((variant) =>
      (!this.selectedColor || variant.color === this.selectedColor) && this.inStock(variant)
    ) || this.variantsValue.find((variant) =>
      !this.selectedColor || variant.color === this.selectedColor
    ) || this.variantsValue[0]
  }

  needsSize() {
    return this.requireSizeValue && this.sizeButtonTargets.length > 0 && !this.selectedSize
  }

  focusSizes() {
    const group = this.hasSizeGroupTarget ? this.sizeGroupTarget : this.sizeButtonTargets[0]
    if (!group) return
    group.scrollIntoView({ behavior: "smooth", block: "center" })
    group.classList.add("is-size-attention")
    this.sizeButtonTargets[0]?.focus({ preventScroll: true })
    clearTimeout(this._sizeFlash)
    this._sizeFlash = setTimeout(() => group.classList.remove("is-size-attention"), 1400)
  }

  inStock(variant) {
    return !this.trackInventoryValue || variant.stock > 0
  }

  validate(event) {
    if (this.needsSize()) {
      event.preventDefault()
      this.pendingPurchaseButton = event.submitter || this.purchaseButtonTargets.find((btn) => btn.name === "checkout") || this.purchaseButtonTargets[0]
      if (this.hasSizeSheetTarget) {
        this.openSizeSheet()
        return
      }
      this.focusSizes()
      return
    }
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
