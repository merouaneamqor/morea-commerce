import { Controller } from "@hotwired/stimulus"

// The attribution rule form. By percentage, each ticked agent gets a percentage box and the total must be 100; with equal parts each ticked
// agent gets the same share (the text says how much). The sources list is shown only when the rule is limited to chosen sources.
export default class extends Controller {
  static targets = ["distribution", "agent", "percent", "percentBox", "summary", "sourcesMode", "sources"]
  static values = { equalLabel: String, totalLabel: String }

  connect() {
    this.distributionChanged()
    this.sourcesChanged()
  }

  get byPercent() {
    return this.distributionTargets.find((radio) => radio.checked)?.value === "percent"
  }

  get chosen() {
    return this.agentTargets.filter((box) => box.checked)
  }

  distributionChanged() {
    // Switching to percentages with nothing typed yet: spread 100 % over the ticked agents.
    if (this.byPercent && this.percentTargets.every((field) => field.value === "")) this.spread()
    this.recalc()
  }

  spread() {
    const chosen = this.chosen
    if (chosen.length === 0) return

    const share = Math.floor(100 / chosen.length)
    let rest = 100 - share * chosen.length
    chosen.forEach((box) => {
      const field = this.fieldFor(box)
      if (field) { field.value = share + (rest > 0 ? 1 : 0); if (rest > 0) rest -= 1 }
    })
  }

  fieldFor(box) {
    return this.percentTargets.find((field) => field.id === box.id.replace("rule_agent_", "rule_percent_"))
  }

  recalc() {
    const percent = this.byPercent
    this.agentTargets.forEach((box) => {
      const row = this.percentBoxTargets.find((candidate) => candidate.contains(this.fieldFor(box)))
      if (row) row.classList.toggle("hidden", !(percent && box.checked))
      const field = this.fieldFor(box)
      if (field) field.disabled = !(percent && box.checked)
    })
    if (!this.hasSummaryTarget) return

    const chosen = this.chosen
    if (percent) {
      const total = chosen.reduce((sum, box) => sum + (parseInt(this.fieldFor(box)?.value, 10) || 0), 0)
      this.summaryTarget.textContent = `${this.totalLabelValue} : ${total} %`
      this.summaryTarget.classList.toggle("text-[#2f7a4a]", total === 100)
      this.summaryTarget.classList.toggle("text-[#b4232a]", total !== 100)
      this.summaryTarget.classList.remove("text-[#6e6e73]")
    } else {
      const share = chosen.length ? Math.round((100 / chosen.length) * 10) / 10 : 0
      this.summaryTarget.textContent = chosen.length ? this.equalLabelValue.replace("%{share}", String(share).replace(".", ",")) : ""
      this.summaryTarget.classList.remove("text-[#2f7a4a]", "text-[#b4232a]")
      this.summaryTarget.classList.add("text-[#6e6e73]")
    }
  }

  sourcesChanged() {
    if (!this.hasSourcesTarget) return

    const chosen = this.sourcesModeTargets.find((radio) => radio.checked)?.value === "chosen"
    this.sourcesTarget.classList.toggle("hidden", !chosen)
    this.sourcesTarget.classList.toggle("flex", chosen)
  }
}
