import { Controller } from "@hotwired/stimulus"

// Submits the surrounding form when a filter or sort control changes
export default class extends Controller {
  submit() {
    this.element.requestSubmit()
  }
}
