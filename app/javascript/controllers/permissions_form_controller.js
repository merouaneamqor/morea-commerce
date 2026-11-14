import { Controller } from "@hotwired/stimulus"

// The permissions form of one person: one card per application with its areas as checkboxes. A card's own box ticks all its areas; the count of applications and
// permissions follows; "Tout sélectionner" / "Effacer" act on every area; the search hides the applications that do not match. The server drops anything the role does not give.
export default class extends Controller {
  static targets = ["area", "group", "card", "search", "apps", "areas"]

  connect() { this.recalc() }

  toggleGroup(event) {
    const card = event.target.closest("[data-card]")
    card.querySelectorAll("[data-area-box]").forEach((box) => { box.checked = event.target.checked })
    this.recalc()
  }

  // The arrow of an application opens its small window; "OK", Escape or a click outside closes it. The boxes inside are part of the form.
  openDetails(event) { event.currentTarget.closest("[data-card]").querySelector("dialog").showModal() }

  closeDetails(event) { event.currentTarget.closest("dialog").close() }

  backdropDetails(event) { if (event.target.tagName === "DIALOG") event.target.close() }

  selectAll() { this.areaTargets.forEach((box) => { box.checked = true }); this.recalc() }

  clear() { this.areaTargets.forEach((box) => { box.checked = false }); this.recalc() }

  filter() {
    const term = this.searchTarget.value.trim().toLowerCase()
    this.cardTargets.forEach((card) => { card.hidden = term !== "" && !card.dataset.search.includes(term) })
  }

  recalc() {
    let apps = 0
    this.cardTargets.forEach((card) => {
      const boxes = [...card.querySelectorAll("[data-area-box]")]
      const checked = boxes.filter((box) => box.checked).length
      const group = card.querySelector("[data-group-box]")
      group.checked = checked === boxes.length && boxes.length > 0
      group.indeterminate = checked > 0 && checked < boxes.length
      const badge = card.querySelector("[data-card-count]")
      if (badge) badge.textContent = `${checked}/${boxes.length}`
      const inDialog = card.querySelector("[data-dialog-count]")
      if (inDialog) inDialog.textContent = `${checked}/${boxes.length}`
      card.classList.toggle("is-on", checked > 0)
      if (checked > 0) apps += 1
    })
    this.appsTarget.textContent = String(apps)
    this.areasTarget.textContent = String(this.areaTargets.filter((box) => box.checked).length)
  }
}
