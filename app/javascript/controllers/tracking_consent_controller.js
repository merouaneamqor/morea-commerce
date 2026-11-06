import { Controller } from "@hotwired/stimulus"

// Records accept/reject for measurement cookies and reloads after grant so pixels can load.
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

  accept(event) {
    event?.preventDefault()
    return this.persist("granted", { reload: true })
  }

  reject(event) {
    event?.preventDefault()
    return this.persist("denied", { reload: false })
  }

  async persist(choice, { reload }) {
    const token = document.querySelector('meta[name="csrf-token"]')?.content
    const body = new URLSearchParams({ choice })
    const response = await fetch(this.urlValue, {
      method: "POST",
      headers: {
        "X-CSRF-Token": token,
        "Content-Type": "application/x-www-form-urlencoded",
        Accept: "application/json"
      },
      credentials: "same-origin",
      body
    })
    if (!response.ok) return
    this.element.remove()
    if (reload) window.location.reload()
  }
}
