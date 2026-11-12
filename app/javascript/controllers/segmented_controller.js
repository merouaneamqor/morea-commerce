import { Controller } from "@hotwired/stimulus"

// An iOS-style segmented switch: one thumb slides under the segment that is chosen. The segments are links that load their page into
// a Turbo frame, so the switch itself never reloads; the thumb moves on the click, before the frame answers, and follows the frame when
// a link inside it changes the view (the frame's content says which view it shows with data-analytics-view).
export default class extends Controller {
  static targets = ["thumb", "item"]
  // "view": the segments are the views of the page; "agent": the segments are the agents, and the whole switch is hidden while no agent is open.
  static values = { by: { type: String, default: "view" } }

  connect() {
    this.sync()
    // The first placement must not slide in from the left edge.
    requestAnimationFrame(() => this.thumbTarget.classList.add("is-ready"))
  }

  sync() {
    const current = this.itemTargets.find((item) => item.getAttribute("aria-current") === "page") || this.itemTargets[0]
    if (current) this.place(current)
  }

  select(event) {
    this.activate(event.currentTarget)
  }

  frameLoaded(event) {
    const body = event.target.querySelector?.("[data-analytics-view]")
    if (!body) return

    const key = this.byValue === "agent" ? body.dataset.analyticsAgent : body.dataset.analyticsView
    const item = this.itemTargets.find((candidate) => candidate.dataset[this.byValue] === key)
    if (this.byValue === "agent") {
      const wasHidden = this.element.hidden
      this.element.hidden = !item
      if (item && wasHidden) this.placeWithoutSlide(item)
    }
    if (item) this.activate(item)
  }

  // Shown for the first time: the thumb appears under its segment instead of sliding in from the edge.
  placeWithoutSlide(item) {
    this.thumbTarget.classList.remove("is-ready")
    this.place(item)
    this.thumbTarget.getBoundingClientRect()
    requestAnimationFrame(() => this.thumbTarget.classList.add("is-ready"))
  }

  activate(item) {
    this.itemTargets.forEach((other) => other.removeAttribute("aria-current"))
    item.setAttribute("aria-current", "page")
    this.place(item)
  }

  place(item) {
    this.thumbTarget.style.width = `${item.offsetWidth}px`
    this.thumbTarget.style.transform = `translateX(${item.offsetLeft - this.thumbTarget.offsetLeft}px)`
  }
}
