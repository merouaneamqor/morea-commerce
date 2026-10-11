import { Controller } from "@hotwired/stimulus"

// Dismisses the informational cookie notice (one tap, no reload).
export default class extends Controller {
  static values = { url: String }

  async accept() {
    const token = document.querySelector('meta[name="csrf-token"]')?.content
    await fetch(this.urlValue, {
      method: "POST",
      headers: {
        "X-CSRF-Token": token,
        "Content-Type": "application/x-www-form-urlencoded",
        Accept: "application/json"
      },
      credentials: "same-origin"
    })
    this.element.remove()
  }
}
