import { Controller } from "@hotwired/stimulus"

// An agent on shift tells the server every 30 seconds that the page is open and visible. If the page is closed, hidden or the phone is
// asleep, the heartbeats stop and the server ends the shift at the last one (Confirmations::Shifts.close_stale!). When it has done so,
// the page reloads and shows "Pointer l'arrivée" again, so nobody believes they are still counted.
export default class extends Controller {
  static values = { url: String, interval: { type: Number, default: 30000 } }

  connect() {
    this.beat = this.beat.bind(this)
    this.visibility = () => { if (!document.hidden) this.beat() }
    document.addEventListener("visibilitychange", this.visibility)
    this.timer = setInterval(this.beat, this.intervalValue)
  }

  disconnect() {
    clearInterval(this.timer)
    document.removeEventListener("visibilitychange", this.visibility)
  }

  async beat() {
    if (document.hidden) return
    const token = document.querySelector("meta[name='csrf-token']")?.content
    try {
      const response = await fetch(this.urlValue, { method: "POST", headers: { "X-CSRF-Token": token, "Accept": "application/json" }, credentials: "same-origin" })
      if (!response.ok) return
      const { open } = await response.json()
      if (!open) window.location.reload()
    } catch (_error) {
      // Offline for a moment: the next beat tries again; the server decides after the grace period.
    }
  }
}
