import { Controller } from "@hotwired/stimulus"

// Toggle single-piece vs two-piece size chart fields on the product admin form.
export default class extends Controller {
  static targets = ["mode", "single", "set"]

  connect() {
    this.toggle()
  }

  toggle() {
    const setMode = this.modeTarget.value === "set"
    this.singleTarget.hidden = setMode
    this.setTarget.hidden = !setMode
    this.setDisabled(this.singleTarget, setMode)
    this.setDisabled(this.setTarget, !setMode)
  }

  setDisabled(root, disabled) {
    root.querySelectorAll("input, select, textarea").forEach((field) => {
      field.disabled = disabled
    })
  }
}
