import { Controller } from "@hotwired/stimulus"

// Fast checkout popup: lock scroll, autofocus name, light hold timer near CTA.
export default class extends Controller {
  static targets = ["dialog", "name", "timer", "urgency"]
  static values = {
    holdSeconds: { type: Number, default: 600 },
    store: String,
    holdingLabel: String,
    expiredLabel: String
  }

  connect() {
    document.documentElement.classList.add("checkout-modal-open")
    this.restoreFocus()
    this.startHold()
  }

  disconnect() {
    document.documentElement.classList.remove("checkout-modal-open")
    this.clearHold()
  }

  restoreFocus() {
    requestAnimationFrame(() => {
      const field = this.hasNameTarget ? this.nameTarget : this.element.querySelector("input:not([type=hidden]), select, textarea")
      if (!field || field.disabled) return
      try {
        field.focus({ preventScroll: true })
      } catch {
        field.focus()
      }
    })
  }

  startHold() {
    if (!this.hasTimerTarget && !this.hasUrgencyTarget) return

    const key = `morea_checkout_hold_${this.storeValue || "store"}`
    let deadline = null
    try {
      const raw = sessionStorage.getItem(key)
      deadline = raw ? Number(raw) : null
    } catch {
      deadline = null
    }

    const now = Date.now()
    if (!deadline || Number.isNaN(deadline) || deadline < now - 60_000) {
      deadline = now + this.holdSecondsValue * 1000
      try {
        sessionStorage.setItem(key, String(deadline))
      } catch {
        // Private mode — timer still runs for this page view.
      }
    }

    this.deadline = deadline
    this.tickHold()
    this.holdTimer = window.setInterval(() => this.tickHold(), 1000)
  }

  tickHold() {
    const remaining = Math.max(0, Math.floor((this.deadline - Date.now()) / 1000))
    if (remaining <= 0) {
      if (this.hasTimerTarget) this.timerTarget.hidden = true
      if (this.hasUrgencyTarget) {
        this.urgencyTarget.textContent = this.expiredLabelValue
        this.urgencyTarget.hidden = false
      }
      this.clearHold()
      return
    }

    const minutes = String(Math.floor(remaining / 60)).padStart(2, "0")
    const seconds = String(remaining % 60).padStart(2, "0")
    if (this.hasTimerTarget) {
      this.timerTarget.textContent = `${minutes}:${seconds}`
      this.timerTarget.hidden = false
    }
    if (this.hasUrgencyTarget && this.holdingLabelValue) {
      this.urgencyTarget.textContent = this.holdingLabelValue.replace("%{time}", `${minutes}:${seconds}`)
      this.urgencyTarget.hidden = false
    }
  }

  clearHold() {
    if (this.holdTimer) {
      window.clearInterval(this.holdTimer)
      this.holdTimer = null
    }
  }
}
