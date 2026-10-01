import { Controller } from "@hotwired/stimulus"

// Gentle fade/slide entrance for gallery elements
export default class extends Controller {
  static values = {
    delay: { type: Number, default: 0 }
  }

  connect() {
    this.element.style.opacity = "0"
    this.element.style.transform = "translateY(18px)"
    this.element.style.transition = "opacity 1.1s ease, transform 1.1s ease"

    requestAnimationFrame(() => {
      setTimeout(() => {
        this.element.style.opacity = "1"
        this.element.style.transform = "translateY(0)"
      }, this.delayValue)
    })
  }
}
