import { Controller } from "@hotwired/stimulus"

// Reports LCP / CLS / INP to /performance/vitals via sendBeacon. No cookies or customer fields.
export default class extends Controller {
  static values = { url: { type: String, default: "/performance/vitals" } }

  connect() {
    if (this.bound) return
    this.bound = true
    this.observe("largest-contentful-paint", (entry) => this.report("LCP", entry.startTime, entry))
    this.observe("layout-shift", (entry) => {
      if (entry.hadRecentInput) return
      this.cls = (this.cls || 0) + entry.value
      this.report("CLS", this.cls, entry)
    })
    this.observe("event", (entry) => {
      if (entry.name !== "pointer" && entry.name !== "keyboard") return
      const delay = entry.duration
      if (typeof delay === "number") this.report("INP", delay, entry)
    }, { type: "event", buffered: true, durationThreshold: 16 })
  }

  observe(type, onEntry, options = { buffered: true }) {
    try {
      const observer = new PerformanceObserver((list) => {
        list.getEntries().forEach(onEntry)
      })
      observer.observe({ type, ...options })
      this.observers = this.observers || []
      this.observers.push(observer)
    } catch (_) {
      // Older browsers skip quietly.
    }
  }

  report(name, value, entry) {
    const body = JSON.stringify({
      name,
      value,
      id: entry?.id || entry?.name || name,
      rating: this.rating(name, value),
      path: window.location.pathname,
      locale: document.documentElement.lang || "",
      navigationType: performance.getEntriesByType?.("navigation")?.[0]?.type || ""
    })
    const blob = new Blob([body], { type: "application/json" })
    if (navigator.sendBeacon) {
      navigator.sendBeacon(this.urlValue, blob)
    }
  }

  rating(name, value) {
    if (name === "LCP") return value <= 2500 ? "good" : value <= 4000 ? "needs-improvement" : "poor"
    if (name === "CLS") return value <= 0.1 ? "good" : value <= 0.25 ? "needs-improvement" : "poor"
    if (name === "INP") return value <= 200 ? "good" : value <= 500 ? "needs-improvement" : "poor"
    return ""
  }

  disconnect() {
    ;(this.observers || []).forEach((observer) => observer.disconnect())
    this.observers = []
  }
}
