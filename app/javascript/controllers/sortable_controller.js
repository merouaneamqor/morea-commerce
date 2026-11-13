import { Controller } from "@hotwired/stimulus"

// Reorders a list with native drag and drop. The existing move buttons remain
// available as keyboard and touch-friendly controls.
export default class extends Controller {
  static targets = ["list", "item", "status"]
  static values = { url: String }

  dragStart(event) {
    this.draggedItem = event.currentTarget
    this.originalOrder = this.itemTargets.map((item) => item.dataset.sectionId)
    this.draggedItem.classList.add("opacity-50")
    event.dataTransfer.effectAllowed = "move"
    event.dataTransfer.setData("text/plain", this.draggedItem.dataset.sectionId)
  }

  dragOver(event) {
    event.preventDefault()
    if (!this.draggedItem || event.currentTarget === this.draggedItem) return

    event.dataTransfer.dropEffect = "move"
    const target = event.currentTarget
    const afterTarget = event.clientY > target.getBoundingClientRect().top + target.offsetHeight / 2
    this.listTarget.insertBefore(this.draggedItem, afterTarget ? target.nextSibling : target)
  }

  drop(event) {
    event.preventDefault()
    if (!this.draggedItem) return

    this.persistOrder()
  }

  dragEnd() {
    this.draggedItem?.classList.remove("opacity-50")
    this.draggedItem = null
  }

  async persistOrder() {
    const orderedIds = this.itemTargets.map((item) => item.dataset.sectionId)

    try {
      const response = await fetch(this.urlValue, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || ""
        },
        body: JSON.stringify({ ordered_ids: orderedIds })
      })

      if (!response.ok) throw new Error(`Reorder failed (${response.status})`)

      this.updatePositionLabels()
      this.updateMoveButtons()
      this.statusTarget.textContent = "Section order saved."
    } catch (_error) {
      this.restoreOriginalOrder()
      this.statusTarget.textContent = "Section order could not be saved. Try again."
    }
  }

  restoreOriginalOrder() {
    if (!this.originalOrder) return

    const itemsById = new Map(this.itemTargets.map((item) => [item.dataset.sectionId, item]))
    this.originalOrder.forEach((id) => this.listTarget.append(itemsById.get(id)))
  }

  updatePositionLabels() {
    this.itemTargets.forEach((item, index) => {
      const badge = item.querySelector(".admin-badge--neutral")
      if (badge) badge.textContent = index + 1
    })
  }

  updateMoveButtons() {
    this.itemTargets.forEach((item, index) => {
      const up = item.querySelector('[aria-label="Move up"]')
      const down = item.querySelector('[aria-label="Move down"]')
      if (up) up.disabled = index === 0
      if (down) down.disabled = index === this.itemTargets.length - 1
    })
  }
}
