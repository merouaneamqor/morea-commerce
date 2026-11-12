import { Controller } from "@hotwired/stimulus"

// Copies a value (a phone number) to the clipboard and flashes the button.
export default class extends Controller {
  static values = { text: String }

  async copy(event) {
    event.preventDefault()
    try {
      await navigator.clipboard.writeText(this.textValue)
      this.element.classList.add("text-[#5b46d6]")
      setTimeout(() => this.element.classList.remove("text-[#5b46d6]"), 900)
    } catch {
      // Clipboard blocked (insecure context): nothing to do, the number stays visible.
    }
  }
}
