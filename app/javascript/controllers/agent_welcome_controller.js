import { Controller } from "@hotwired/stimulus"

// Two glass windows in the middle of the screen for an agent:
//  - the welcome (name, word of the day, and the clock-in button when they are not on shift), once per sign-in;
//  - a congratulation each time they pass another hundred handled orders today.
// What was already shown is remembered in this browser only (sessionStorage for the welcome, localStorage for the milestone).
export default class extends Controller {
  static targets = ["welcome", "milestone"]
  static values = { welcomeKey: String, milestoneKey: String, milestone: Number }

  connect() {
    if (!this.read(sessionStorage, this.welcomeKeyValue)) {
      this.show(this.welcomeTarget)
    } else {
      this.maybeMilestone()
    }
  }

  // "C'est parti", "Plus tard", or the clock-in button itself (the form is sent right after this runs).
  closeWelcome() {
    this.write(sessionStorage, this.welcomeKeyValue, "1")
    this.hide(this.welcomeTarget)
    this.maybeMilestone()
  }

  closeMilestone() {
    this.write(localStorage, this.milestoneKeyValue, String(this.milestoneValue))
    this.hide(this.milestoneTarget)
  }

  maybeMilestone() {
    if (!this.hasMilestoneTarget || this.milestoneValue < 1) return
    const seen = parseInt(this.read(localStorage, this.milestoneKeyValue) || "0", 10)
    if (this.milestoneValue > seen) this.show(this.milestoneTarget)
  }

  show(element) { element.hidden = false }
  hide(element) { element.hidden = true }

  read(store, key) { try { return store.getItem(key) } catch (_error) { return null } }
  write(store, key, value) { try { store.setItem(key, value) } catch (_error) { /* storage blocked: it just shows again next time */ } }
}
