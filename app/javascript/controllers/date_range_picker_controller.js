import { Controller } from "@hotwired/stimulus"

// The one date range picker of the platform. The presets are plain links rendered by the server (they work without
// JavaScript); this controller adds the custom range: two months side by side (one on a phone), click once for the
// start and once for the end, the days in between highlighted, nothing applied until "Appliquer".
//
// All dates are "YYYY-MM-DD" strings and plain {y, m, d} numbers: no JavaScript Date is built from a local time, so the
// browser's timezone can never move a day. "Today" comes from the server (the store's timezone).
const DAY = 86400000
const parse = (text) => { const [y, m, d] = text.split("-").map(Number); return { y, m: m - 1, d } }
const iso = ({ y, m, d }) => `${y}-${String(m + 1).padStart(2, "0")}-${String(d).padStart(2, "0")}`
const order = ({ y, m, d }) => y * 10000 + (m + 1) * 100 + d
const daysBetween = (a, b) => Math.round((Date.UTC(b.y, b.m, b.d) - Date.UTC(a.y, a.m, a.d)) / DAY) + 1
const monthLength = (y, m) => new Date(Date.UTC(y, m + 1, 0)).getUTCDate()
const mondayOffset = (y, m) => (new Date(Date.UTC(y, m, 1)).getUTCDay() + 6) % 7 // weeks start on Monday
const addMonths = ({ y, m }, n) => { const t = y * 12 + m + n; return { y: Math.floor(t / 12), m: ((t % 12) + 12) % 12 } }

const CELL = "grid size-9 place-items-center rounded-lg text-sm transition"
const STATES = {
  edge: "bg-[#5b46d6] font-semibold text-white",
  inside: "bg-[#eeebfd] text-[#5b46d6]",
  plain: "text-[#10162a] hover:bg-[#e9ecf1]",
  future: "cursor-not-allowed text-[#cfc8c3]"
}

export default class extends Controller {
  static targets = ["panel", "button", "calendar", "startField", "endField", "count", "apply", "months", "customToggle"]
  static values = { config: Object }

  connect() {
    this.cfg = this.configValue
    this.today = parse(this.cfg.today)
    this.media = window.matchMedia("(min-width: 768px)")
    this.onMedia = () => { if (!this.panelTarget.hidden) this.build() }
    this.onOutside = (event) => { if (!this.element.contains(event.target)) this.close() }
    this.onKey = (event) => { if (event.key === "Escape") { this.close(); this.buttonTarget.focus() } }
    this.media.addEventListener("change", this.onMedia)
    this.reset()
  }

  disconnect() {
    this.media.removeEventListener("change", this.onMedia)
    document.removeEventListener("click", this.onOutside)
    document.removeEventListener("keydown", this.onKey)
  }

  // The selection starts as the range the page shows; it changes only when the user applies.
  reset() {
    this.start = parse(this.cfg.from)
    this.end = parse(this.cfg.to)
    this.hover = null
    this.last = { y: this.end.y, m: this.end.m } // the last month shown (the right one on a wide screen)
  }

  toggle() { this.panelTarget.hidden ? this.open() : this.close() }

  open() {
    this.reset()
    this.panelTarget.hidden = false
    this.buttonTarget.setAttribute("aria-expanded", "true")
    this.build()
    setTimeout(() => { document.addEventListener("click", this.onOutside); document.addEventListener("keydown", this.onKey) }, 0)
  }

  close() {
    this.panelTarget.hidden = true
    this.buttonTarget.setAttribute("aria-expanded", "false")
    document.removeEventListener("click", this.onOutside)
    document.removeEventListener("keydown", this.onKey)
  }

  // On a phone the calendar stays hidden until "Plage personnalisée" is tapped; on a wide screen it is always there.
  showCustom() {
    this.calendarTarget.classList.remove("hidden")
    this.build()
  }

  cancel() { this.reset(); this.close() }

  apply() {
    if (!this.end) return
    const url = new URL(this.cfg.url, window.location.origin)
    Object.entries(this.cfg.extra || {}).forEach(([key, value]) => { if (value !== "") url.searchParams.set(key, value) })
    url.searchParams.set("from", iso(this.start))
    url.searchParams.set("to", iso(this.end))
    const preset = this.cfg.presets.find((p) => p.from === iso(this.start) && p.to === iso(this.end))
    if (preset) url.searchParams.set("preset", preset.key)
    const target = url.pathname + url.search
    window.Turbo ? window.Turbo.visit(target) : window.location.assign(target)
  }

  // --- calendar ---

  wide() { return this.media.matches }

  previousMonth() { this.last = addMonths(this.last, -1); this.build() }

  nextMonth() { if (this.canGoNext()) { this.last = addMonths(this.last, 1); this.build() } }

  canGoNext() { return order({ ...this.last, d: 1 }) < order({ ...this.today, d: 1 }) }

  build() {
    const months = this.wide() ? [addMonths(this.last, -1), this.last] : [this.last]
    this.monthsTarget.replaceChildren(...months.map((month, index) => this.monthBlock(month, index === 0, index === months.length - 1)))
    this.paint()
  }

  monthBlock(month, first, lastOne) {
    const wrap = document.createElement("div")
    wrap.className = "min-w-0 flex-1"
    const head = document.createElement("div")
    head.className = "mb-2 flex items-center justify-between"
    head.append(first ? this.arrow(-1) : this.spacer(), this.title(month), lastOne ? this.arrow(1) : this.spacer())
    wrap.append(head)

    const grid = document.createElement("div")
    grid.className = "grid grid-cols-7 gap-y-0.5 text-center"
    this.cfg.weekdays.forEach((name) => {
      const cell = document.createElement("span")
      cell.className = "pb-1 text-[11px] font-medium text-[#6b7280]"
      cell.textContent = name
      grid.append(cell)
    })
    for (let i = 0; i < mondayOffset(month.y, month.m); i++) grid.append(document.createElement("span"))
    for (let d = 1; d <= monthLength(month.y, month.m); d++) grid.append(this.dayButton({ ...month, d }))
    wrap.append(grid)
    return wrap
  }

  title(month) {
    const el = document.createElement("p")
    el.className = "text-sm font-semibold"
    el.textContent = `${this.cfg.months[month.m]} ${month.y}`
    return el
  }

  spacer() { const el = document.createElement("span"); el.className = "size-7"; return el }

  arrow(direction) {
    const button = document.createElement("button")
    button.type = "button"
    button.className = "grid size-7 place-items-center rounded-lg text-[#4b5260] hover:bg-[#e9ecf1] disabled:cursor-not-allowed disabled:opacity-30"
    button.setAttribute("aria-label", direction < 0 ? this.cfg.labels.previous : this.cfg.labels.next)
    const flip = (direction < 0) !== this.cfg.rtl // the chevron points to the start side; RTL mirrors it
    button.innerHTML = `<svg viewBox="0 0 24 24" class="size-4 fill-none stroke-current [stroke-width:2] [stroke-linecap:round] [stroke-linejoin:round]" aria-hidden="true"><path d="${flip ? "m15 18-6-6 6-6" : "m9 18 6-6-6-6"}"/></svg>`
    if (direction > 0) button.disabled = !this.canGoNext()
    button.addEventListener("click", () => (direction < 0 ? this.previousMonth() : this.nextMonth()))
    return button
  }

  dayButton(date) {
    const button = document.createElement("button")
    button.type = "button"
    button.dataset.date = iso(date)
    button.textContent = String(date.d)
    button.setAttribute("aria-label", `${date.d} ${this.cfg.months[date.m]} ${date.y}`)
    if (order(date) > order(this.today)) {
      button.disabled = true // no dates in the future
    } else {
      button.addEventListener("click", () => this.pick(date))
      button.addEventListener("mouseenter", () => { if (this.picking() && this.hover !== iso(date)) { this.hover = iso(date); this.paint() } })
    }
    return button
  }

  picking() { return this.start && !this.end }

  // Click once for the start, again for the end; a second click before the first swaps them.
  pick(date) {
    if (!this.picking()) {
      this.start = date
      this.end = null
    } else {
      let [a, b] = [this.start, date]
      if (order(b) < order(a)) [a, b] = [b, a]
      this.start = a
      this.end = b
    }
    this.hover = null
    this.paint()
  }

  // Colours the days, fills the fields and the day count, enables or disables Appliquer.
  paint() {
    const startKey = this.start && order(this.start)
    const endKey = this.end ? order(this.end) : (this.hover ? order(parse(this.hover)) : null)
    const [low, high] = endKey && startKey > endKey ? [endKey, startKey] : [startKey, endKey]
    this.monthsTarget.querySelectorAll("button[data-date]").forEach((button) => {
      const date = parse(button.dataset.date)
      const key = order(date)
      const future = key > order(this.today)
      let state = "plain"
      if (future) state = "future"
      else if (key === low || key === high) state = "edge"
      else if (low && high && key > low && key < high) state = "inside"
      button.className = `${CELL} ${STATES[state]}`
      button.setAttribute("aria-pressed", state === "edge" ? "true" : "false")
    })
    const format = (date) => date ? `${date.d} ${this.cfg.monthsShort[date.m]} ${date.y}` : "—"
    this.startFieldTarget.textContent = format(this.start)
    this.endFieldTarget.textContent = this.end ? format(this.end) : this.cfg.labels.pickEnd
    const days = this.end ? daysBetween(this.start, this.end) : null
    this.countTarget.textContent = days === null ? "" : (days === 1 ? this.cfg.labels.daysOne : this.cfg.labels.daysOther.replace("%{count}", days))
    this.applyTarget.disabled = !this.end
  }
}
