import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["promoPanel", "promoToggle"]

  connect() {
    if (this.hasPromoPanelTarget && !this.promoPanelTarget.hidden) {
      this.promoPanelTarget.querySelector("input")?.focus()
    }
  }

  togglePromo() {
    const panel = this.promoPanelTarget
    const opening = panel.hidden
    panel.hidden = !opening
    if (opening) panel.querySelector("input")?.focus()
  }
}
