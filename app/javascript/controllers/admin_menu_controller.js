import { Controller } from "@hotwired/stimulus"

// Slide-in admin sidebar on small screens
export default class extends Controller {
  toggle() {
    this.element.classList.toggle("is-menu-open")
  }

  close() {
    this.element.classList.remove("is-menu-open")
  }
}
