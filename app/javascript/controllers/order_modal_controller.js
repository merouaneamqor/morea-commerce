import { Controller } from "@hotwired/stimulus"

// The "Nouvelle commande" window: a glass dialog inside the order-modal Turbo frame. Closing empties the frame.
// The page behind does not scroll while it is open; Escape and a click on the dimmed backdrop close it.
export default class extends Controller {
  connect() {
    document.body.classList.add("overflow-hidden")
    this.onKey = (event) => { if (event.key === "Escape") this.close() }
    document.addEventListener("keydown", this.onKey)
    this.element.querySelector("input:not([type=hidden])")?.focus()
  }

  disconnect() {
    document.body.classList.remove("overflow-hidden")
    document.removeEventListener("keydown", this.onKey)
  }

  backdrop(event) {
    if (event.target === this.element) this.close()
  }

  close() {
    const frame = this.element.closest("turbo-frame")
    if (frame) frame.innerHTML = ""
    else window.history.back()
  }
}
