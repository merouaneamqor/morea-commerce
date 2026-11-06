import { Controller } from "@hotwired/stimulus"

// Slide-out bag on <body>; the drawer element is replaced by Turbo Streams
export default class extends Controller {
  static targets = ["drawer"]

  connect() {
    this.onKeydown = (event) => {
      if (!this.hasDrawerTarget || !this.drawerTarget.classList.contains("is-open")) return
      if (event.key === "Escape") {
        this.close()
        return
      }
      if (event.key === "Tab") this.trapFocus(event)
    }
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
    this.previousFocus = document.activeElement
    this.drawerTarget.classList.add("is-open")
    this.drawerTarget.setAttribute("aria-hidden", "false")
    document.documentElement.classList.add("is-locked")
    this.focusable()[0]?.focus()
  }

  close() {
    if (!this.hasDrawerTarget) return
    this.drawerTarget.classList.remove("is-open")
    this.drawerTarget.setAttribute("aria-hidden", "true")
    document.documentElement.classList.remove("is-locked")
    if (this.previousFocus?.focus) this.previousFocus.focus()
  }

  focusable() {
    return Array.from(
      this.drawerTarget.querySelectorAll(
        'a[href], button:not([disabled]), textarea, input, select, [tabindex]:not([tabindex="-1"])'
      )
    ).filter((el) => !el.hasAttribute("disabled") && el.getAttribute("aria-hidden") !== "true")
  }

  trapFocus(event) {
    const nodes = this.focusable()
    if (nodes.length === 0) return
    const first = nodes[0]
    const last = nodes[nodes.length - 1]
    if (event.shiftKey && document.activeElement === first) {
      event.preventDefault()
      last.focus()
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault()
      first.focus()
    }
  }
}
