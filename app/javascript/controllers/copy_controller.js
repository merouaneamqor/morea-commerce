import { Controller } from "@hotwired/stimulus"

// Copies a value (a phone number) to the clipboard and flashes the button.
export default class extends Controller {
  static values = { text: String }

  async copy(event) {
    event.preventDefault()
    try {
      await navigator.clipboard.writeText(this.textValue)
      this.element.classList.add("text-[#1d1d1f]")
      setTimeout(() => this.element.classList.remove("text-[#1d1d1f]"), 900)
    } catch {
      // Clipboard blocked (insecure context): nothing to do, the number stays visible.
    }
  }
}
