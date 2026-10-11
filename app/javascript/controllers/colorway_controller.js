import { Controller } from "@hotwired/stimulus"

// Pick a photo, describe or click the garment, preview a dye, then save it.
export default class extends Controller {
  static targets = [ "form", "stage", "dots", "points", "hex", "name", "results", "original", "mask", "result", "report", "submit" ]
  static values = { previewUrl: String }

  connect() {
    if (!this.hasFormTarget) return
    this.points = this.readPoints()
    this.syncStage()
    this.renderDots()
  }

  selectSource() {
    this.points = []
    this.pointsTarget.value = "[]"
    this.renderDots()
    this.syncStage()
    this.hideResults()
  }

  preset(event) {
    event.preventDefault()
    this.hexTarget.value = event.currentTarget.dataset.hex
    this.nameTarget.value = event.currentTarget.dataset.name
  }

  addPoint(event) {
    const rect = this.stageTarget.getBoundingClientRect()
    if (!rect.width || !rect.height) return

    const x = (event.clientX - rect.left) / rect.width
    const y = (event.clientY - rect.top) / rect.height
    if (x < 0 || y < 0 || x > 1 || y > 1) return

    this.points.push([ Number(x.toFixed(4)), Number(y.toFixed(4)) ])
    this.points = this.points.slice(-12)
    this.pointsTarget.value = JSON.stringify(this.points)
    this.renderDots()
  }

  clearPoints(event) {
    event.preventDefault()
    this.points = []
    this.pointsTarget.value = "[]"
    this.renderDots()
  }

  async preview(event) {
    event.preventDefault()
    this.setBusy(true)
    this.reportTarget.textContent = "Finding the garment and recoloring it…"
    this.resultsTarget.hidden = false

    try {
      const response = await fetch(this.previewUrlValue, {
        method: "POST",
        headers: {
          Accept: "application/json",
          "X-CSRF-Token": document.querySelector("meta[name='csrf-token']").content
        },
        body: new FormData(this.formTarget)
      })
      const payload = await response.json()
      if (!response.ok) throw new Error(payload.error || "Recolor failed.")

      this.originalTarget.src = this.stageTarget.src
      this.maskTarget.src = payload.mask
      this.resultTarget.src = payload.image
      this.reportTarget.textContent = payload.report?.summary || "Preview ready."
    } catch (error) {
      this.reportTarget.textContent = error.message
    } finally {
      this.setBusy(false)
    }
  }

  syncStage() {
    const selected = this.formTarget.querySelector("input[name='attachment_id']:checked")
    if (selected?.dataset.colorwayUrl) this.stageTarget.src = selected.dataset.colorwayUrl
  }

  renderDots() {
    this.dotsTarget.replaceChildren()
    this.points.forEach(([ x, y ]) => {
      const dot = document.createElement("span")
      dot.style.left = `${x * 100}%`
      dot.style.top = `${y * 100}%`
      this.dotsTarget.append(dot)
    })
  }

  readPoints() {
    try {
      const parsed = JSON.parse(this.pointsTarget.value || "[]")
      return Array.isArray(parsed) ? parsed : []
    } catch {
      return []
    }
  }

  hideResults() {
    this.resultsTarget.hidden = true
    this.reportTarget.textContent = ""
  }

  setBusy(busy) {
    this.submitTargets.forEach((button) => { button.disabled = busy })
  }
}
