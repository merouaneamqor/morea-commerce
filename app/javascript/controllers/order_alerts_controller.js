import { Controller } from "@hotwired/stimulus"

// Opt-in browser push for new orders. The system notification uses the OS sound;
// while an admin tab is open, the service worker also reports the order here so
// the page can play the Seallo chime.
export default class extends Controller {
  static targets = ["toggle", "label"]
  static values = {
    publicKey: String,
    subscribeUrl: String,
    onLabel: String,
    offLabel: String,
    blockedLabel: String
  }

  connect() {
    this.supported = "serviceWorker" in navigator && "PushManager" in window && "Notification" in window && this.hasPublicKeyValue
    this.toggleTarget.hidden = !this.supported
    if (!this.supported) return

    this.handleMessage = this.handleMessage.bind(this)
    navigator.serviceWorker.addEventListener("message", this.handleMessage)
    this.refresh().catch(() => this.render(false))
  }

  disconnect() {
    navigator.serviceWorker?.removeEventListener("message", this.handleMessage)
  }

  toggle() {
    if (this.enabled) {
      this.disable().catch(() => this.render(true))
    } else {
      this.enable().catch(() => this.render(false))
    }
  }

  async refresh() {
    const registration = await navigator.serviceWorker.register("/admin/service-worker.js", { scope: "/admin" })
    const subscription = await registration.pushManager.getSubscription()
    this.render(Boolean(subscription) && Notification.permission === "granted")
  }

  async enable() {
    const permission = await Notification.requestPermission()
    if (permission !== "granted") return this.render(false, { blocked: permission === "denied" })

    const registration = await navigator.serviceWorker.ready
    const subscription = await registration.pushManager.subscribe({
      userVisibleOnly: true,
      applicationServerKey: this.applicationServerKey()
    })
    await this.send("POST", subscription.toJSON())
    this.chime() // The click that enabled alerts also unlocks audio for the chime.
    this.render(true)
  }

  async disable() {
    const registration = await navigator.serviceWorker.ready
    const subscription = await registration.pushManager.getSubscription()
    if (subscription) {
      await this.send("DELETE", { endpoint: subscription.endpoint })
      await subscription.unsubscribe()
    }
    this.render(false)
  }

  handleMessage(event) {
    if (event.data?.kind === "new_order") this.chime()
  }

  async send(method, subscription) {
    const token = document.querySelector("meta[name='csrf-token']")?.content
    const response = await fetch(this.subscribeUrlValue, {
      method,
      headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": token },
      credentials: "same-origin",
      body: JSON.stringify({ subscription })
    })
    if (!response.ok) throw new Error(`Push subscription failed: ${response.status}`)
  }

  // Two rising tones, distinct from the system sound and quiet enough for a shared desk.
  chime() {
    try {
      const AudioCtx = window.AudioContext || window.webkitAudioContext
      this.audio ||= new AudioCtx()
      if (this.audio.state === "suspended") this.audio.resume()
      const start = this.audio.currentTime
      ;[[880, 0], [1320, 0.16]].forEach(([frequency, offset]) => {
        const oscillator = this.audio.createOscillator()
        const gain = this.audio.createGain()
        oscillator.type = "sine"
        oscillator.frequency.value = frequency
        gain.gain.setValueAtTime(0.0001, start + offset)
        gain.gain.exponentialRampToValueAtTime(0.25, start + offset + 0.02)
        gain.gain.exponentialRampToValueAtTime(0.0001, start + offset + 0.45)
        oscillator.connect(gain).connect(this.audio.destination)
        oscillator.start(start + offset)
        oscillator.stop(start + offset + 0.5)
      })
    } catch (_) {
      // Browsers can block audio until the page has been used; the notification still shows.
    }
  }

  render(on, { blocked = false } = {}) {
    this.enabled = on
    this.toggleTarget.setAttribute("aria-pressed", String(on))
    this.toggleTarget.title = blocked ? this.blockedLabelValue : ""
    this.labelTarget.textContent = on ? this.onLabelValue : this.offLabelValue
  }

  applicationServerKey() {
    const padding = "=".repeat((4 - (this.publicKeyValue.length % 4)) % 4)
    const base64 = (this.publicKeyValue + padding).replace(/-/g, "+").replace(/_/g, "/")
    return Uint8Array.from(atob(base64), (char) => char.charCodeAt(0))
  }
}
