import { Controller } from "@hotwired/stimulus"

// One small tooltip for every chart of a page: any element with data-tip shows its text next to it on hover or focus.
// The charts are drawn on the server; this only adds the hover layer (the same numbers are in the table view).
export default class extends Controller {
  connect() {
    this.tip = document.createElement("div")
    this.tip.setAttribute("role", "tooltip")
    this.tip.className = "pointer-events-none fixed z-[70] max-w-[16rem] rounded-lg bg-[#1c1c1e] px-2.5 py-1.5 text-[12px] leading-snug text-white shadow-lg"
    this.tip.hidden = true
    document.body.appendChild(this.tip)
  }

  disconnect() {
    this.tip?.remove()
  }

  show(event) {
    const target = event.target.closest?.("[data-tip]")
    if (!target || !this.element.contains(target)) return this.hide()

    this.tip.textContent = target.dataset.tip
    this.tip.hidden = false
    const box = target.getBoundingClientRect()
    const tipBox = this.tip.getBoundingClientRect()
    const left = Math.min(Math.max(box.left + box.width / 2 - tipBox.width / 2, 8), window.innerWidth - tipBox.width - 8)
    const above = box.top - tipBox.height - 8
    this.tip.style.left = `${Math.round(left)}px`
    this.tip.style.top = `${Math.round(above >= 8 ? above : box.bottom + 8)}px`
  }

  hide() {
    this.tip.hidden = true
  }
}
