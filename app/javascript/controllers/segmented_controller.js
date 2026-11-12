import { Controller } from "@hotwired/stimulus"

// An iOS-style segmented switch: one thumb slides under the segment that is chosen. The segments are links that load their page into
// a Turbo frame, so the switch itself never reloads; the thumb moves on the click, before the frame answers, and follows the frame when
// a link inside it changes the view (the frame's content says which view it shows with data-analytics-view).
export default class extends Controller {
  static targets = ["thumb", "item"]

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
    const view = event.target.querySelector?.("[data-analytics-view]")?.dataset.analyticsView
    const item = this.itemTargets.find((candidate) => candidate.dataset.view === view)
    if (item) this.activate(item)
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
