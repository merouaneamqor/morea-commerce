import { Controller } from "@hotwired/stimulus"

// Replaces the PDP gallery with the selected variant's photos. If a variant
// has no photos, the original product gallery remains visible.
export default class extends Controller {
  static targets = ["shot"]

  show(event) {
    const urls = event.detail?.variant?.images
    if (!Array.isArray(urls) || urls.length === 0) {
      this.restoreProductGallery()
      return
    }

    this.shotTargets.forEach((shot, index) => {
      const image = this.imageFor(shot)
      if (!image) return

      this.rememberProductImage(image)
      const url = urls[index]
      if (url) {
        image.src = url
        image.removeAttribute("srcset")
      } else {
        this.restoreProductImage(image)
      }
    })
  }

  restoreProductGallery() {
    this.shotTargets.forEach((shot) => {
      const image = this.imageFor(shot)
      if (image) this.restoreProductImage(image)
    })
  }

  imageFor(shot) {
    return shot.querySelector("img")
  }

  rememberProductImage(image) {
    if (image.dataset.variantGalleryOriginalSrc) return

    image.dataset.variantGalleryOriginalSrc = image.getAttribute("src") || ""
    image.dataset.variantGalleryOriginalSrcset = image.getAttribute("srcset") || ""
  }

  restoreProductImage(image) {
    this.rememberProductImage(image)
    image.src = image.dataset.variantGalleryOriginalSrc

    const srcset = image.dataset.variantGalleryOriginalSrcset
    if (srcset) image.setAttribute("srcset", srcset)
    else image.removeAttribute("srcset")
  }
}
