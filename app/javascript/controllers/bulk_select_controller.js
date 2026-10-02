import { Controller } from "@hotwired/stimulus"

// Checkbox selection for batch actions: select all, per-group, and a live count
export default class extends Controller {
  static targets = ["box", "all", "action", "count"]

  connect() {
    this.update()
  }

  toggleAll(event) {
    this.boxTargets.forEach((box) => { box.checked = event.currentTarget.checked })
    this.update()
  }

  toggleGroup(event) {
    const group = event.currentTarget.dataset.group
    this.boxTargets.filter((box) => box.dataset.group === group).forEach((box) => { box.checked = event.currentTarget.checked })
    this.update()
  }

  update() {
    const selected = this.boxTargets.filter((box) => box.checked).length
    this.actionTargets.forEach((button) => { button.disabled = selected === 0 })
    if (this.hasAllTarget) {
      this.allTarget.checked = selected > 0 && selected === this.boxTargets.length
      this.allTarget.indeterminate = selected > 0 && selected < this.boxTargets.length
    }
    if (this.hasCountTarget) {
      this.countTarget.textContent = selected ? `${selected} selected` : "Select images to edit them together."
    }
  }
}
