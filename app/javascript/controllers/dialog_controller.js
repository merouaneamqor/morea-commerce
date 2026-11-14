import { Controller } from "@hotwired/stimulus"

// Opens a native <dialog> in the middle of the screen from a button; it closes with its own "Fermer" button, the Escape key or a click on the backdrop.
export default class extends Controller {
  static targets = ["dialog"]

  open() { this.dialogTarget.showModal() }

  close() { this.dialogTarget.close() }

  backdrop(event) { if (event.target === this.dialogTarget) this.close() }
}
