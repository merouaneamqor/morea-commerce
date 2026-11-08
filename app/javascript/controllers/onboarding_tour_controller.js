import { Controller } from "@hotwired/stimulus"

// Checklist dismiss + a short spotlight tour over seller sidebar destinations.
export default class extends Controller {
  static targets = ["panel"]
  static values = {
    storeId: Number,
    dismissLabel: String,
    nextLabel: String,
    doneLabel: String,
    steps: { type: Array, default: [] }
  }

  connect() {
    if (this.dismissed()) {
      this.hidePanel()
      return
    }
    this.element.hidden = false
    this.element.style.opacity = "0"
    this.element.style.transform = "translateY(10px)"
    this.element.style.transition = "opacity 0.45s ease, transform 0.45s ease"
    requestAnimationFrame(() => {
      this.element.style.opacity = "1"
      this.element.style.transform = "translateY(0)"
    })
  }

  disconnect() {
    this.teardownTour()
  }

  dismiss() {
    this.persistDismiss()
    this.hidePanel()
    this.teardownTour()
  }

  start(event) {
    event?.preventDefault()
    if (!this.stepsValue.length) return
    this.index = 0
    this.renderTourStep()
  }

  next(event) {
    event?.preventDefault()
    this.index += 1
    if (this.index >= this.stepsValue.length) {
      this.teardownTour()
      return
    }
    this.renderTourStep()
  }

  // --- persistence ---------------------------------------------------------

  storageKey() {
    return `seallo.onboarding.dismissed.${this.storeIdValue}`
  }

  dismissed() {
    try {
      return window.localStorage.getItem(this.storageKey()) === "1"
    } catch (_) {
      return false
    }
  }

  persistDismiss() {
    try {
      window.localStorage.setItem(this.storageKey(), "1")
    } catch (_) { /* Keep in-memory hide only. */ }
  }

  hidePanel() {
    this.element.hidden = true
  }

  // --- tour overlay --------------------------------------------------------

  renderTourStep() {
    const step = this.stepsValue[this.index]
    if (!step) return this.teardownTour()

    const target = this.findNav(step.target)
    this.ensureOverlay()
    this.placeSpotlight(target)
    this.placeCard(step, target)
  }

  findNav(key) {
    const nodes = Array.from(document.querySelectorAll(`[data-onboarding-nav="${key}"]`))
    return nodes.find((node) => node.offsetParent !== null) || nodes[0] || null
  }

  ensureOverlay() {
    if (this.overlay) return
    this.overlay = document.createElement("div")
    this.overlay.className = "onboarding-tour"
    this.overlay.setAttribute("role", "dialog")
    this.overlay.setAttribute("aria-modal", "true")
    this.overlay.innerHTML = `
      <div class="onboarding-tour__veil" data-tour-veil></div>
      <div class="onboarding-tour__spot" data-tour-spot hidden></div>
      <div class="onboarding-tour__card" data-tour-card>
        <p class="onboarding-tour__progress" data-tour-progress></p>
        <h3 class="onboarding-tour__title" data-tour-title></h3>
        <p class="onboarding-tour__body" data-tour-body></p>
        <div class="onboarding-tour__actions">
          <button type="button" class="onboarding-tour__ghost" data-tour-skip>${this.dismissLabelValue}</button>
          <button type="button" class="onboarding-tour__primary" data-tour-next></button>
        </div>
      </div>
    `
    document.body.appendChild(this.overlay)
    this.overlay.querySelector("[data-tour-skip]").addEventListener("click", () => this.dismiss())
    this.overlay.querySelector("[data-tour-next]").addEventListener("click", (e) => this.next(e))
    this.overlay.querySelector("[data-tour-veil]").addEventListener("click", () => this.teardownTour())
    this.onKey = (e) => {
      if (e.key === "Escape") this.teardownTour()
      if (e.key === "Enter" || e.key === "ArrowRight") this.next(e)
    }
    document.addEventListener("keydown", this.onKey)
  }

  placeSpotlight(target) {
    const spot = this.overlay.querySelector("[data-tour-spot]")
    const veil = this.overlay.querySelector("[data-tour-veil]")
    if (!target) {
      spot.hidden = true
      veil.hidden = false
      return
    }
    const rect = target.getBoundingClientRect()
    // Spot cutout uses its own box-shadow veil; hide the full-page veil to avoid double dimming.
    veil.hidden = true
    spot.hidden = false
    spot.style.top = `${Math.max(8, rect.top - 8)}px`
    spot.style.left = `${Math.max(8, rect.left - 8)}px`
    spot.style.width = `${rect.width + 16}px`
    spot.style.height = `${rect.height + 16}px`
    target.scrollIntoView({ block: "nearest", behavior: "smooth" })
  }

  placeCard(step, target) {
    const card = this.overlay.querySelector("[data-tour-card]")
    const last = this.index >= this.stepsValue.length - 1
    this.overlay.querySelector("[data-tour-progress]").textContent =
      `${this.index + 1} / ${this.stepsValue.length}`
    this.overlay.querySelector("[data-tour-title]").textContent = step.title
    this.overlay.querySelector("[data-tour-body]").textContent = step.body
    this.overlay.querySelector("[data-tour-next]").textContent =
      last ? this.doneLabelValue : this.nextLabelValue

    const rect = target?.getBoundingClientRect()
    const cardWidth = Math.min(320, window.innerWidth - 24)
    let top = 96
    let left = Math.max(12, (window.innerWidth - cardWidth) / 2)
    if (rect) {
      top = Math.min(window.innerHeight - 220, rect.bottom + 16)
      left = Math.min(window.innerWidth - cardWidth - 12, Math.max(12, rect.left))
      if (top + 200 > window.innerHeight) top = Math.max(12, rect.top - 210)
    }
    card.style.width = `${cardWidth}px`
    card.style.top = `${top}px`
    card.style.left = `${left}px`
  }

  teardownTour() {
    if (this.onKey) document.removeEventListener("keydown", this.onKey)
    this.onKey = null
    this.overlay?.remove()
    this.overlay = null
  }
}
