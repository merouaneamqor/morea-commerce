import { Controller } from "@hotwired/stimulus"

// One-shot / page event bridge. Fires when the element connects, then removes
// itself when data-pixel-event-ephemeral-value is true (AddToCart streams).
export default class extends Controller {
  static values = {
    name: String,
    payload: { type: Object, default: {} },
    ephemeral: { type: Boolean, default: false }
  }

  connect() {
    requestAnimationFrame(() => this.fire())
  }

  fire() {
    if (!this.nameValue) return

    const bridge = window.MoreaPixels
    if (bridge) {
      bridge.track(this.nameValue, this.payloadValue || {})
    }

    if (this.ephemeralValue) this.element.remove()
  }
}
