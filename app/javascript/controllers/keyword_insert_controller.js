import { Controller } from "@hotwired/stimulus"

// Buttons that put a keyword such as {{nom_client}} into the message text where the cursor is.
export default class extends Controller {
  static targets = ["text"]

  insert(event) {
    const keyword = `{{${event.params.keyword}}}`
    const field = this.textTarget
    const start = field.selectionStart ?? field.value.length
    const end = field.selectionEnd ?? field.value.length
    field.setRangeText(keyword, start, end, "end")
    field.focus()
    field.dispatchEvent(new Event("input", { bubbles: true }))
  }
}
