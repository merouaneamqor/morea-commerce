import { Controller } from "@hotwired/stimulus"

// A small two-way switch: one button per view, one panel per view, only the chosen panel is shown.
// Without scripts the first panel stays visible and the others are hidden, which is still readable.
export default class extends Controller {
  static targets = ["button", "panel"]

  show(event) {
    this.select(event.params.key)
  }

  select(key) {
    this.panelTargets.forEach((panel) => { panel.hidden = panel.dataset.key !== key })
    this.buttonTargets.forEach((button) => {
      const active = button.dataset.key === key
      button.setAttribute("aria-pressed", String(active))
      button.classList.toggle("bg-[#1c1c1e]", active)
      button.classList.toggle("text-white", active)
      button.classList.toggle("text-[#6e6e73]", !active)
    })
  }
}
