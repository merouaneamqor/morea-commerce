import { Controller } from "@hotwired/stimulus"

// Slide-out bag on <body>; the drawer element is replaced by Turbo Streams
export default class extends Controller {
  static targets = ["drawer"]

  connect() {
    this.onKeydown = (event) => { if (event.key === "Escape") this.close() }
    document.addEventListener("keydown", this.onKeydown)
  }

  disconnect() {
    document.removeEventListener("keydown", this.onKeydown)
    document.documentElement.classList.remove("is-locked")
  }

  drawerTargetConnected(drawer) {
    if (drawer.dataset.open === "true") requestAnimationFrame(() => this.open())
  }

  open(event) {
    if (!this.hasDrawerTarget) return
    event?.preventDefault()
    this.drawerTarget.classList.add("is-open")
    this.drawerTarget.setAttribute("aria-hidden", "false")
    document.documentElement.classList.add("is-locked")
  }

  close() {
    if (!this.hasDrawerTarget) return
    this.drawerTarget.classList.remove("is-open")
    this.drawerTarget.setAttribute("aria-hidden", "true")
    document.documentElement.classList.remove("is-locked")
  }
}
