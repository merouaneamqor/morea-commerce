import { Controller } from "@hotwired/stimulus"

// A color gallery can have any number of photos, even without product photos.
export default class extends Controller {
  static targets = ["gallery", "shotTemplate"]

  show(event) {
    const urls = event.detail?.variant?.images
    if (!Array.isArray(urls) || urls.length === 0) {
      this.restoreProductGallery()
      return
    }

    const key = JSON.stringify(urls)
    if (key === this.currentGalleryKey) return

    this.productShots ||= Array.from(this.galleryTarget.children, (shot) => shot.cloneNode(true))
    const shots = urls.map((url, index) => {
      const shot = this.shotTemplateTarget.content.firstElementChild.cloneNode(true)
      const image = shot.querySelector("img")
      const lead = index === 0
      shot.classList.toggle("pdp__shot--lead", lead)
      image.src = url
      image.loading = lead ? "eager" : "lazy"
      image.setAttribute("fetchpriority", lead ? "high" : "auto")
      image.sizes = lead ? "(max-width: 768px) 90vw, 58vw" : "(max-width: 768px) 90vw, 29vw"
      return shot
    })

    this.galleryTarget.replaceChildren(...shots)
    this.currentGalleryKey = key
  }

  restoreProductGallery() {
    if (!this.currentGalleryKey) return

    this.galleryTarget.replaceChildren(...this.productShots.map((shot) => shot.cloneNode(true)))
    this.currentGalleryKey = null
  }
}
