import { Controller } from "@hotwired/stimulus"

// Smooth scroll to next section (homepage decompression)
export default class extends Controller {
  scroll(event) {
    event.preventDefault()
    const id = this.element.getAttribute("href")
    const target = document.querySelector(id)
    if (!target) return

    target.scrollIntoView({ behavior: "smooth", block: "start" })
  }
}
