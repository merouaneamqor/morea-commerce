import { Controller } from "@hotwired/stimulus"

// Slide-in admin sidebar on small screens
export default class extends Controller {
  static targets = ["menuButton", "sidebar"]

  connect() {
    this.syncExpanded()
  }

  toggle() {
    this.element.classList.toggle("is-menu-open")
    this.syncExpanded()
  }

  close() {
    this.element.classList.remove("is-menu-open")
    this.syncExpanded()
  }

  closeOnNavigate(event) {
    const link = event.target.closest("a")
    if (!link) return
    this.close()
  }

  syncExpanded() {
    if (!this.hasMenuButtonTarget) return
    this.menuButtonTarget.setAttribute("aria-expanded", this.element.classList.contains("is-menu-open") ? "true" : "false")
  }
}
