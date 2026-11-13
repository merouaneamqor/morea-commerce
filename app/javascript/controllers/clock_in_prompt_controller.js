import { Controller } from "@hotwired/stimulus"

// The notice that asks an agent to clock in when they open the site or sign in. "Plus tard" hides it for this browser session only:
// it comes back the next time they open the site (an agent who left the page is clocked out automatically).
export default class extends Controller {
  static targets = ["box"]
  static values = { key: { type: String, default: "clockInPromptDismissed" } }

  connect() {
    let dismissed = false
    try { dismissed = sessionStorage.getItem(this.keyValue) === "1" } catch (_error) { /* storage blocked: show it */ }
    this.boxTarget.hidden = dismissed
  }

  dismiss() {
    try { sessionStorage.setItem(this.keyValue, "1") } catch (_error) { /* ignore */ }
    this.boxTarget.hidden = true
  }
}
