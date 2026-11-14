import { Controller } from "@hotwired/stimulus"

// A notice as a floating gray-glass window at the top of the screen: it fades in, stays for `duration` milliseconds and goes away by itself. Without scripts it simply stays
// on the page. Turbo does not keep it in its page cache (data-turbo-temporary on the container), so going back never shows an old notice again.
export default class extends Controller {
  static values = { duration: { type: Number, default: 1000 } }

  connect() {
    this.element.classList.add("is-pre")
    requestAnimationFrame(() => requestAnimationFrame(() => this.element.classList.remove("is-pre")))
    this.timer = setTimeout(() => this.leave(), this.durationValue)
  }

  disconnect() {
    clearTimeout(this.timer)
    clearTimeout(this.removal)
  }

  leave() {
    this.element.classList.add("is-pre")
    this.removal = setTimeout(() => this.element.remove(), 320)
  }
}
