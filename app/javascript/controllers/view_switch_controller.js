import { Controller } from "@hotwired/stimulus"

// A small two-way switch: one button per view, one panel per view, only the chosen panel is shown. The switch is an iOS-style
// segmented control: a dark thumb slides under the chosen button. Without scripts the first panel stays visible and the others are
// hidden, which is still readable.
export default class extends Controller {
  static targets = ["button", "panel", "thumb"]
  static values = { param: String }

  connect() {
    this.placeThumb()
    // The first placement must not slide in from the left edge.
    requestAnimationFrame(() => { if (this.hasThumbTarget) this.thumbTarget.classList.add("is-ready") })
  }

  show(event) {
    this.select(event.params.key)
  }

  select(key) {
    this.panelTargets.forEach((panel) => { panel.hidden = panel.dataset.key !== key })
    this.buttonTargets.forEach((button) => {
      const active = button.dataset.key === key
      button.setAttribute("aria-pressed", String(active))
      button.classList.toggle("text-white", active)
      button.classList.toggle("text-[#6e6e73]", !active)
    })
    this.placeThumb()
    // With a param name the address follows the chosen panel, so a reload or a shared link opens the same one.
    if (this.hasParamValue && this.paramValue) {
      const url = new URL(window.location.href)
      url.searchParams.set(this.paramValue, key)
      window.history.replaceState(window.history.state, "", url)
    }
  }

  placeThumb() {
    if (!this.hasThumbTarget) return

    const active = this.buttonTargets.find((button) => button.getAttribute("aria-pressed") === "true") || this.buttonTargets[0]
    if (!active) return

    this.thumbTarget.style.width = `${active.offsetWidth}px`
    this.thumbTarget.style.transform = `translateX(${active.offsetLeft - this.thumbTarget.offsetLeft}px)`
  }
}
