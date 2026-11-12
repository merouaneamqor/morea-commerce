import { Controller } from "@hotwired/stimulus"

// The call window. Opening it claims the order and starts the call clock on the server (POST call); the timer shows the time
// since that start. "Hang up" or closing without a result abandons the call (a call longer than a few seconds still counts as one
// attempt). A result button saves the edits and the result in one request (POST finish_call), then offers the next order.
export default class extends Controller {
  static targets = ["timer", "dot", "error", "form", "notes", "callbackRow", "callbackAt", "buttons", "result", "lines", "subtotal", "total", "done", "doneText", "nextButton"]
  static values = {
    callUrl: String, abandonUrl: String, finishUrl: String, touchUrl: String, panelUrlTemplate: String, currency: String,
    shippingCents: Number, discountCents: Number, cancelNeedsReason: String, callbackNeedsTime: String, saved: String
  }

  connect() {
    this.started = false
    this.finished = false
    this.dirty = false
    this.nextOrderId = null
    this.setButtons(false)
    this.start()
  }

  disconnect() {
    this.stopTimers()
    if (this.started && !this.finished) this.abandon()
  }

  async start() {
    try {
      const response = await this.post(this.callUrlValue)
      const data = await response.json()
      if (!response.ok) return this.fail(data.error)

      this.started = true
      this.offset = Date.parse(data.server_now) - Date.now()
      this.startedAt = Date.parse(data.call_started_at)
      this.tick()
      this.timerHandle = window.setInterval(() => this.tick(), 1000)
      this.touchHandle = window.setInterval(() => this.post(this.touchUrlValue).catch(() => {}), 60000)
      this.setButtons(true)
    } catch {
      this.fail("—")
    }
  }

  tick() {
    const seconds = Math.max(Math.round((Date.now() + this.offset - this.startedAt) / 1000), 0)
    const minutes = String(Math.floor(seconds / 60)).padStart(2, "0")
    this.timerTarget.textContent = `${minutes}:${String(seconds % 60).padStart(2, "0")}`
  }

  stopTimers() {
    window.clearInterval(this.timerHandle)
    window.clearInterval(this.touchHandle)
  }

  edited() { this.dirty = true }

  prevent(event) { event.preventDefault() }

  // The totals as the quantities and variants change. A preview only: the server prices the saved order.
  recalc() {
    let subtotal = 0
    this.linesTarget.querySelectorAll("[data-line]").forEach((line) => {
      if (line.hidden) return
      const variant = line.querySelector("select")
      const unit = variant ? Number(variant.selectedOptions[0]?.dataset.priceCents || line.dataset.unitCents) : Number(line.dataset.unitCents)
      const quantity = Math.max(parseInt(line.querySelector("[data-qty]").value, 10) || 0, 0)
      const total = unit * quantity
      subtotal += total
      line.querySelector("[data-line-total]").textContent = this.money(total)
    })
    this.subtotalTarget.textContent = this.money(subtotal)
    this.totalTarget.textContent = this.money(Math.max(subtotal - this.discountCentsValue + this.shippingCentsValue, 0))
  }

  removeLine(event) {
    const visible = [...this.linesTarget.querySelectorAll("[data-line]")].filter((line) => !line.hidden)
    if (visible.length <= 1) return                           // an order keeps at least one product
    const line = event.currentTarget.closest("[data-line]")
    line.hidden = true
    line.querySelectorAll("input, select").forEach((field) => { field.disabled = true })
    this.dirty = true
    this.recalc()
  }

  askCallback() {
    this.callbackRowTarget.classList.remove("hidden")
    this.callbackRowTarget.classList.add("flex")
    this.callbackAtTarget.focus()
  }

  async finish(event) {
    const outcome = event.params.outcome
    const notes = this.notesTarget.value.trim()
    this.hideError()
    if (outcome === "cancelled" && !notes) {
      this.notesTarget.focus()
      return this.showError(this.cancelNeedsReasonValue)
    }
    if (outcome === "callback" && !this.callbackAtTarget.value) {
      this.callbackAtTarget.focus()
      return this.showError(this.callbackNeedsTimeValue)
    }
    if (!this.formTarget.reportValidity()) return

    const body = new FormData()
    body.append("outcome", outcome)
    body.append("notes", notes)
    if (outcome === "callback") body.append("callback_at", this.callbackAtTarget.value)
    // The edits travel only when something was changed and the result is one that needs the order to be right.
    if (this.dirty && !["wrong_number", "no_answer"].includes(outcome)) {
      new FormData(this.formTarget).forEach((value, key) => { if (key.startsWith("order[")) body.append(key, value) })
    }

    this.setButtons(false)
    try {
      const response = await this.post(this.finishUrlValue, body)
      const data = await response.json()
      if (!response.ok) {
        this.setButtons(true)
        return this.showError(data.error)
      }
      this.finished = true
      this.stopTimers()
      this.nextOrderId = data.next_order_id
      this.formTarget.classList.add("hidden")
      this.doneTarget.classList.remove("hidden")
      this.doneTextTarget.textContent = this.savedValue
      this.nextButtonTarget.hidden = !this.nextOrderId
      this.dotTarget.classList.replace("bg-[#2f9d5c]", "bg-[#8e8e93]")
    } catch {
      this.setButtons(true)
      this.showError("—")
    }
  }

  next() {
    if (!this.nextOrderId) return
    const frame = this.element.closest("turbo-frame")
    frame.src = this.panelUrlTemplateValue.replace("__ID__", this.nextOrderId)
  }

  closeAndRefresh() {
    const frame = this.element.closest("turbo-frame")
    frame.innerHTML = ""
    window.Turbo?.visit(window.location.href, { action: "replace" })
  }

  abandon() {
    const token = document.querySelector("meta[name=csrf-token]")?.content
    fetch(this.abandonUrlValue, { method: "POST", headers: { "X-CSRF-Token": token, Accept: "application/json" }, credentials: "same-origin", keepalive: true }).catch(() => {})
  }

  post(url, body) {
    const token = document.querySelector("meta[name=csrf-token]")?.content
    return fetch(url, { method: "POST", body, headers: { "X-CSRF-Token": token, Accept: "application/json" }, credentials: "same-origin" })
  }

  setButtons(enabled) {
    this.resultTargets.forEach((button) => { button.disabled = !enabled })
  }

  fail(message) {
    this.showError(message)
    this.setButtons(false)
    this.dotTarget.classList.replace("bg-[#2f9d5c]", "bg-[#e5484d]")
  }

  showError(message) {
    this.errorTarget.textContent = message
    this.errorTarget.classList.remove("hidden")
  }

  hideError() { this.errorTarget.classList.add("hidden") }

  money(cents) {
    return `${Math.round(cents / 100).toLocaleString("fr-MA")} ${this.currencyValue}`
  }
}
