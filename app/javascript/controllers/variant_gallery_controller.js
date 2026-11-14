import { Controller } from "@hotwired/stimulus"

// Swaps the PDP gallery to the selected variant's photos. Falls back to the
// product gallery when the variant has none. Syncs on connect so a lazy-loaded
// picker change that fired earlier is still applied. Prefers the live picker
// controller's variants when present so HTML-escaped data attributes are not
// the only source of truth after connect.
export default class extends Controller {
  static targets = ["gallery", "shotTemplate"]
  static values = { productImages: Array }

  connect() {
    const variant = this.selectedVariant()
    const hasVariantImages = Array.isArray(variant?.images) && variant.images.length > 0
    if (!hasVariantImages && this.hasGalleryTarget) {
      this.placeholderShots = Array.from(this.galleryTarget.children, (shot) => shot.cloneNode(true))
    }
    this.syncFromSelection()
  }

  show(event) {
    this.renderVariant(event.detail?.variant || null)
  }

  syncFromSelection() {
    this.renderVariant(this.selectedVariant())
  }

  selectedVariant() {
    const id = this.selectedVariantId()
    if (!id) return null

    return this.variantsList().find((variant) => String(variant.id) === String(id)) || null
  }

  selectedVariantId() {
    const picker = this.pickerController()
    if (picker?.hasVariantIdTarget) return picker.variantIdTarget.value

    return this.element.querySelector("[data-variant-picker-target='variantId']")?.value
  }

  variantsList() {
    const picker = this.pickerController()
    if (picker && Array.isArray(picker.variantsValue) && picker.variantsValue.length > 0) {
      return picker.variantsValue
    }

    const raw = this.element.getAttribute("data-variant-picker-variants-value")
    if (!raw) return []

    try {
      const parsed = JSON.parse(raw)
      return Array.isArray(parsed) ? parsed : []
    } catch (_error) {
      return []
    }
  }

  pickerController() {
    const app = this.application
    if (!app?.getControllerForElementAndIdentifier) return null

    return app.getControllerForElementAndIdentifier(this.element, "variant-picker")
  }

  renderVariant(variant) {
    const urls = variant?.images
    if (!Array.isArray(urls) || urls.length === 0) {
      this.restoreProductGallery()
      return
    }

    this.renderUrls(urls)
  }

  restoreProductGallery() {
    if (this.productImagesValue.length > 0) {
      this.renderUrls(this.productImagesValue, { productFallback: true })
      return
    }

    if (!this.currentGalleryKey) return
    if (!this.hasGalleryTarget) return

    if (this.placeholderShots?.length) {
      this.galleryTarget.replaceChildren(...this.placeholderShots.map((shot) => shot.cloneNode(true)))
    } else {
      this.galleryTarget.replaceChildren()
    }
    this.currentGalleryKey = null
    this.renderedOnce = true
    this.resetGalleryScroll()
  }

  renderUrls(urls, { productFallback = false } = {}) {
    const key = productFallback ? null : JSON.stringify(urls)
    if (key === this.currentGalleryKey) return
    if (productFallback && this.currentGalleryKey === null && this.renderedOnce) return
    if (!this.hasShotTemplateTarget || !this.hasGalleryTarget) return

    const shots = urls.map((url, index) => {
      const shot = this.shotTemplateTarget.content.firstElementChild.cloneNode(true)
      const image = shot.querySelector("img")
      const lead = index === 0
      shot.classList.toggle("pdp__shot--lead", lead)
      if (image) {
        image.src = url
        image.removeAttribute("srcset")
        image.loading = lead ? "eager" : "lazy"
        image.setAttribute("fetchpriority", lead ? "high" : "auto")
        image.sizes = lead ? "(max-width: 768px) 90vw, 58vw" : "(max-width: 768px) 90vw, 29vw"
      }
      return shot
    })

    this.galleryTarget.replaceChildren(...shots)
    this.currentGalleryKey = key
    this.renderedOnce = true
    this.resetGalleryScroll()
  }

  resetGalleryScroll() {
    if (!this.hasGalleryTarget) return
    this.galleryTarget.scrollLeft = 0
  }
}
