import { Controller } from "@hotwired/stimulus"

// Layout bridge. Fires PageView when this element mounts (each Turbo body
// swap) and drains events queued while the controller was still lazy-loading.
// Do not also listen for turbo:load: that event often fires before lazy
// connect on the first paint, then again after connect on later visits, which
// duplicates PageView.
export default class extends Controller {
  static values = {
    metaId: String,
    tiktokId: String,
    analyticsId: String,
    userData: { type: Object, default: {} }
  }

  connect() {
    window.MoreaPixels = this
    this.flushQueue()
    this.trackPageView()
  }

  disconnect() {
    if (window.MoreaPixels === this) window.MoreaPixels = null
  }

  flushQueue() {
    const queue = window.MoreaPixelQueue || []
    window.MoreaPixelQueue = []
    queue.forEach((entry) => {
      if (!entry || !entry.name) return
      this.track(entry.name, entry.payload || {})
    })
  }

  trackPageView() {
    this.meta("PageView")
    this.tiktokPage()
    this.analyticsPage()
  }

  track(name, payload = {}) {
    const metaName = name === "CompletePayment" ? "Purchase" : name
    const tiktokName = name === "Purchase" ? "CompletePayment" : name
    const data = this.normalizePayload(payload)

    this.meta(metaName, data)
    this.tiktok(tiktokName, data)
    this.analytics(metaName, data)
  }

  normalizePayload(payload) {
    if (!payload || typeof payload !== "object" || Array.isArray(payload)) return {}
    const data = { ...payload }
    if (data.content_ids && !Array.isArray(data.content_ids)) {
      data.content_ids = [ String(data.content_ids) ]
    }
    if (Array.isArray(data.content_ids)) {
      data.content_ids = data.content_ids.map((id) => String(id))
    }
    if (Array.isArray(data.contents)) {
      data.contents = data.contents.map((row) => {
        if (!row || typeof row !== "object") return row
        return {
          ...row,
          id: row.id != null ? String(row.id) : row.id,
          quantity: row.quantity != null ? Number(row.quantity) : row.quantity,
          item_price: row.item_price != null ? Number(row.item_price) : row.item_price
        }
      })
    }
    return data
  }

  meta(eventName, payload = {}) {
    if (!this.metaIdValue || typeof window.fbq !== "function") return

    const data = { ...payload }
    const eventID = data.event_id || data.eventID
    delete data.event_id
    delete data.eventID
    delete data.user_data

    if (!data.contents && Array.isArray(data.content_ids)) {
      data.contents = data.content_ids.map((id) => ({
        id: String(id),
        quantity: Number(data.quantity || data.num_items || 1),
        item_price: data.value != null && (data.quantity || data.num_items)
          ? Number((Number(data.value) / Number(data.quantity || data.num_items || 1)).toFixed(2))
          : data.value
      }))
    }

    const options = {}
    if (eventID) options.eventID = String(eventID)

    if (Object.keys(data).length && Object.keys(options).length) {
      window.fbq("track", eventName, data, options)
    } else if (Object.keys(data).length) {
      window.fbq("track", eventName, data)
    } else if (Object.keys(options).length) {
      window.fbq("track", eventName, {}, options)
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
    if (eventName === "page" || eventName === "PageView") {
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
    delete mapped.event_id
    delete mapped.eventID
    delete mapped.user_data
    if (!mapped.contents && Array.isArray(mapped.content_ids)) {
      mapped.contents = mapped.content_ids.map((id) => ({
        content_id: String(id),
        content_type: mapped.content_type || "product",
        quantity: Number(mapped.quantity || mapped.num_items || 1),
        price: mapped.value != null ? Number(mapped.value) : undefined
      }))
    }
    return mapped
  }

  analyticsPage() {
    if (!this.analyticsIdValue || typeof window.gtag !== "function") return
    window.gtag("event", "page_view", {
      page_location: window.location.href,
      page_path: window.location.pathname + window.location.search,
      page_title: document.title
    })
  }

  analytics(eventName, payload = {}) {
    if (!this.analyticsIdValue || typeof window.gtag !== "function") return
    if (eventName === "PageView") {
      this.analyticsPage()
      return
    }

    const params = {}
    if (payload.value != null) params.value = payload.value
    if (payload.currency) params.currency = payload.currency
    if (payload.search_string) params.search_term = payload.search_string
    if (payload.content_name) params.item_list_name = payload.content_name
    if (payload.content_category) params.item_category = payload.content_category
    if (payload.content_ids) {
      params.items = payload.content_ids.map((id, index) => {
        const row = Array.isArray(payload.contents) ? payload.contents[index] : null
        return {
          item_id: String(id),
          item_name: payload.content_name,
          quantity: row?.quantity || payload.quantity || 1,
          price: row?.item_price
        }
      })
    }

    const map = {
      ViewContent: "view_item",
      AddToCart: "add_to_cart",
      InitiateCheckout: "begin_checkout",
      Purchase: "purchase",
      Search: "search",
      ViewCategory: "view_item_list"
    }
    window.gtag("event", map[eventName] || eventName, params)
  }
}
