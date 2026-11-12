import { Controller } from "@hotwired/stimulus"

// Submits the surrounding form when a filter or sort control changes, or shortly after typing stops in a search box.
// After the page reloads with the search applied, the box gets its focus back with the cursor at the end.
export default class extends Controller {
  connect() {
    const box = this.element.querySelector("[data-auto-submit-restore='true']")
    if (!box) return
    box.focus()
    box.setSelectionRange(box.value.length, box.value.length)
  }

  disconnect() {
    clearTimeout(this.timer)
  }

  submit() {
    this.element.requestSubmit()
  }

  debounce() {
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.submit(), 600)
  }
}
