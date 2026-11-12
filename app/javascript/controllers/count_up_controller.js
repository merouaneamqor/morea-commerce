import { Controller } from "@hotwired/stimulus"

// Counts a whole number up from 0 when the element appears, then puts the server-rendered text back so the
// final figure is exactly what the server printed. No animation when the user prefers reduced motion.
export default class extends Controller {
  static values = { target: Number, suffix: String, duration: { type: Number, default: 1100 } }

  connect() {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches || this.targetValue <= 0) return

    this.original = this.element.textContent
    const format = new Intl.NumberFormat("fr-FR")
    const start = performance.now()
    const tick = (now) => {
      const progress = Math.min((now - start) / this.durationValue, 1)
      const eased = 1 - Math.pow(1 - progress, 3)
      const shown = Math.round(this.targetValue * eased)
      this.element.textContent = `${format.format(shown)} ${this.suffixValue}`
      if (progress < 1) {
        this.frame = requestAnimationFrame(tick)
      } else {
        this.element.textContent = this.original
      }
    }
    this.frame = requestAnimationFrame(tick)
  }

  disconnect() {
    if (this.frame) cancelAnimationFrame(this.frame)
    if (this.original) this.element.textContent = this.original
  }
}
