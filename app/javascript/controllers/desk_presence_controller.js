import { Controller } from "@hotwired/stimulus"

// Keeps a confirmation agent's "pages open" stat alive while a platform tab is visible.
// Hiding every tab stops the heartbeat; closing the page sends one last "away".
const HEARTBEAT_MS = 20000

export default class extends Controller {
  static values = { url: String }

  connect() {
    this.pingIfVisible()
    this.timer = setInterval(() => this.pingIfVisible(), HEARTBEAT_MS)
    this.onVisibility = () => this.pingIfVisible()
    this.onLeave = () => this.leave()
    document.addEventListener("visibilitychange", this.onVisibility)
    window.addEventListener("pagehide", this.onLeave)
  }

  disconnect() {
    clearInterval(this.timer)
    document.removeEventListener("visibilitychange", this.onVisibility)
    window.removeEventListener("pagehide", this.onLeave)
  }

  pingIfVisible() {
    if (document.visibilityState === "visible") this.ping()
  }

  ping() {
    fetch(this.urlValue, {
      method: "POST",
      credentials: "same-origin",
      headers: this.headers(),
      body: new URLSearchParams({ away: "0" })
    }).catch(() => {})
  }

  leave() {
    const body = new FormData()
    body.append("away", "1")
    const token = document.querySelector("meta[name='csrf-token']")?.content
    if (token) body.append("authenticity_token", token)
    if (navigator.sendBeacon) navigator.sendBeacon(this.urlValue, body)
  }

  headers() {
    const token = document.querySelector("meta[name='csrf-token']")?.content
    return { "X-CSRF-Token": token || "", "Accept": "text/html" }
  }
}
