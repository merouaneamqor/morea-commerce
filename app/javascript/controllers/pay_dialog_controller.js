import { Controller } from "@hotwired/stimulus"

// The "pay an agent" window: choose an agent, then tick the delivered orders to pay (each pays the agent's rate), how they are paid, a reference and
// an optional proof. Only the chosen agent's orders are shown and sent; the server checks every order again and computes the amount itself.
export default class extends Controller {
  static targets = ["dialog", "agent", "section", "submit", "count", "amount"]
  static values = { currency: String }

  open(event) {
    const id = event.params?.agent
    if (id) this.agentTarget.value = String(id)
    this.refresh()
    this.dialogTarget.showModal()
  }

  close() { this.dialogTarget.close() }

  backdrop(event) { if (event.target === this.dialogTarget) this.close() }

  // The agent changed: show their orders only; the other agents' boxes are disabled so they are not sent.
  refresh() {
    const chosen = this.agentTarget.value
    this.sectionTargets.forEach((section) => {
      const active = section.dataset.agentId === chosen
      section.hidden = !active
      section.querySelectorAll("input[type=checkbox]").forEach((box) => { box.disabled = !active; if (!active) box.checked = false })
    })
    this.recalc()
  }

  toggleAll(event) {
    const section = event.target.closest("[data-agent-id]")
    section.querySelectorAll("input[name='order_ids[]']").forEach((box) => { box.checked = event.target.checked })
    this.recalc()
  }

  recalc() {
    const section = this.sectionTargets.find((candidate) => !candidate.hidden)
    const count = section ? section.querySelectorAll("input[name='order_ids[]']:checked").length : 0
    const rate = section ? parseInt(section.dataset.rateCents || "0", 10) : 0
    this.countTarget.textContent = String(count)
    this.amountTarget.textContent = `${(count * rate / 100).toLocaleString(undefined, { maximumFractionDigits: 2 })} ${this.currencyValue}`
    this.submitTarget.disabled = count === 0
  }
}
