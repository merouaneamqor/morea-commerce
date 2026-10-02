import { Controller } from "@hotwired/stimulus"

// Gives the fixed nav a solid backdrop once the page has scrolled
export default class extends Controller {
  connect() {
    this.update = this.update.bind(this)
    window.addEventListener("scroll", this.update, { passive: true })
    this.update()
  }

  disconnect() {
    window.removeEventListener("scroll", this.update)
  }

  update() {
    this.element.classList.toggle("is-scrolled", window.scrollY > 24)
  }
}
