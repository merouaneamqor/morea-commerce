import { Controller } from "@hotwired/stimulus"

// Gentle fade/slide entrance for gallery elements, with optional staggered children.
export default class extends Controller {
  static values = {
    delay: { type: Number, default: 0 },
    stagger: { type: Boolean, default: false }
  }

  connect() {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return

    const items = this.staggerValue
      ? Array.from(this.element.querySelectorAll("[data-reveal-item]"))
      : [this.element]

    if (!items.length) return

    items.forEach((el, index) => {
      el.style.opacity = "0"
      el.style.transform = "translateY(22px)"
      el.style.transition = "opacity 1.05s cubic-bezier(0.22, 1, 0.36, 1), transform 1.05s cubic-bezier(0.22, 1, 0.36, 1)"

      requestAnimationFrame(() => {
        setTimeout(() => {
          el.style.opacity = "1"
          el.style.transform = "translateY(0)"
        }, this.delayValue + (this.staggerValue ? index * 110 : 0))
      })
    })
  }
}
