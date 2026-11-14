import { Controller } from "@hotwired/stimulus"

// One-shot / page event bridge. Controllers are lazy-loaded, so the layout
// bridge may not exist yet when this connects — queue until it does.
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

    const entry = {
      name: this.nameValue,
      payload: this.normalizePayload(this.payloadValue)
    }

    const bridge = window.MoreaPixels
    if (bridge) {
      bridge.track(entry.name, entry.payload)
    } else {
      window.MoreaPixelQueue = window.MoreaPixelQueue || []
      window.MoreaPixelQueue.push(entry)
    }

    if (this.ephemeralValue) this.element.remove()
  }

  normalizePayload(payload) {
    if (!payload) return {}
    if (typeof payload === "string") {
      try {
        const parsed = JSON.parse(payload)
        return parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : {}
      } catch (_) {
        return {}
      }
    }
    if (typeof payload === "object" && !Array.isArray(payload)) return payload
    return {}
  }
}
