import { Controller } from "@hotwired/stimulus"

// Loads once in the layout. Fires PageView / page on every Turbo visit.
export default class extends Controller {
  static values = {
    metaId: String,
    tiktokId: String
  }

  connect() {
    this.onLoad = () => this.trackPageView()
    document.addEventListener("turbo:load", this.onLoad)
    window.MoreaPixels = this
  }

  disconnect() {
    document.removeEventListener("turbo:load", this.onLoad)
    if (window.MoreaPixels === this) window.MoreaPixels = null
  }

  trackPageView() {
    this.meta("PageView")
    this.tiktokPage()
  }

  track(name, payload = {}) {
    const metaName = name === "CompletePayment" ? "Purchase" : name
    const tiktokName = name === "Purchase" ? "CompletePayment" : name

    this.meta(metaName, payload)
    this.tiktok(tiktokName, payload)
  }

  meta(eventName, payload = {}) {
    if (!this.metaIdValue || typeof window.fbq !== "function") return
    if (payload && Object.keys(payload).length) {
      window.fbq("track", eventName, payload)
    } else {
      window.fbq("track", eventName)
    }
  }

  tiktokPage() {
    if (!this.tiktokIdValue || !window.ttq || typeof window.ttq.page !== "function") return
    window.ttq.page()
  }

  tiktok(eventName, payload = {}) {
    if (!this.tiktokIdValue || !window.ttq || typeof window.ttq.track !== "function") return
    if (eventName === "page") {
      this.tiktokPage()
      return
    }
    if (payload && Object.keys(payload).length) {
      window.ttq.track(eventName, this.tiktokPayload(payload))
    } else {
      window.ttq.track(eventName)
    }
  }

  tiktokPayload(payload) {
    const mapped = { ...payload }
    if (mapped.content_ids) {
      mapped.contents = mapped.content_ids.map((id) => ({ content_id: String(id), content_type: mapped.content_type || "product" }))
    }
    return mapped
  }
}
