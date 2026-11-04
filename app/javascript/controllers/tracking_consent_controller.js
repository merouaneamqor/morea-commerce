import { Controller } from "@hotwired/stimulus"

// Dismisses the informational cookie notice (one tap, no reload).
export default class extends Controller {
  static values = { url: String }

  connect() {
    this.resizeObserver = new ResizeObserver(() => {
      document.body.style.setProperty("--cookie-notice-height", `${this.element.getBoundingClientRect().height}px`)
    })
    this.resizeObserver.observe(this.element)
  }

  disconnect() {
    this.resizeObserver?.disconnect()
    document.body.classList.remove("has-cookie-notice")
    document.body.style.removeProperty("--cookie-notice-height")
  }

  async accept() {
    const token = document.querySelector('meta[name="csrf-token"]')?.content
    const response = await fetch(this.urlValue, {
      method: "POST",
      headers: {
        "X-CSRF-Token": token,
        "Content-Type": "application/x-www-form-urlencoded",
        Accept: "application/json"
      },
      credentials: "same-origin"
    })
    if (response.ok) this.element.remove()
  }
}
