import { Controller } from "@hotwired/stimulus"

// Ticks from the server's shift start, so a reload or tab change shows the true elapsed time.
export default class extends Controller {
  static values = { startedAt: String }

  connect() {
    this.startedAt = Date.parse(this.startedAtValue)
    this.render()
    this.timer = setInterval(() => this.render(), 1000)
  }

  disconnect() {
    clearInterval(this.timer)
  }

  render() {
    const seconds = Math.max(0, Math.floor((Date.now() - this.startedAt) / 1000))
    const parts = [Math.floor(seconds / 3600), Math.floor((seconds % 3600) / 60), seconds % 60]
    this.element.textContent = parts.map(part => String(part).padStart(2, "0")).join(":")
  }
}
