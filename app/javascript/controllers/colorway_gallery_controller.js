import { Controller } from "@hotwired/stimulus"

// Swap product photos when the shopper picks a color that has a saved colorway.
export default class extends Controller {
  static targets = [ "shot" ]
  static values = { colorways: Object }

  show(event) {
    const urls = this.urlsFor(event.detail?.color)
    this.shotTargets.forEach((shot, index) => {
      const img = shot.querySelector("img")
      if (!img) return
      if (!img.dataset.colorwayOriginalSrc) {
        img.dataset.colorwayOriginalSrc = img.getAttribute("src") || ""
        img.dataset.colorwayOriginalSrcset = img.getAttribute("srcset") || ""
      }

      const next = urls && urls[index]
      if (next) {
        img.src = next
        img.srcset = ""
      } else {
        img.src = img.dataset.colorwayOriginalSrc
        img.srcset = img.dataset.colorwayOriginalSrcset
      }
    })
  }

  urlsFor(color) {
    if (!color) return null
    const map = this.colorwaysValue || {}
    if (map[color]) return map[color]
    const key = Object.keys(map).find((name) => name.toLowerCase() === String(color).toLowerCase())
    return key ? map[key] : null
  }
}
