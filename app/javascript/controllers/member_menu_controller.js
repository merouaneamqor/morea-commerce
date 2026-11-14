import { Controller } from "@hotwired/stimulus"

// The three-dots menu of a team member: a dropdown of actions (a popover in the top layer, so the table never clips it) and the windows it opens (details, edit, role). The
// edits are made in place: nothing leaves the team page.
export default class extends Controller {
  static targets = ["menu", "dialog"]

  toggle(event) {
    const menu = this.menuTarget
    if (menu.matches(":popover-open")) { menu.hidePopover(); return }

    const anchor = event.currentTarget.getBoundingClientRect()
    menu.showPopover()
    menu.style.position = "fixed"
    menu.style.inset = "auto"
    menu.style.margin = "0"
    // Under the button when there is room, above it otherwise; always inside the window.
    const margin = 8
    const height = menu.offsetHeight
    const room = window.innerHeight - anchor.bottom - margin
    const top = room >= height + 6 ? anchor.bottom + 6 : Math.max(margin, anchor.top - height - 6)
    menu.style.maxHeight = `${window.innerHeight - 2 * margin}px`
    menu.style.overflowY = "auto"
    menu.style.top = `${Math.min(top, window.innerHeight - height - margin > margin ? window.innerHeight - height - margin : margin)}px`
    menu.style.left = `${Math.min(Math.max(margin, anchor.right - menu.offsetWidth), window.innerWidth - menu.offsetWidth - margin)}px`
  }

  open(event) {
    this.menuTarget.hidePopover()
    this.dialogTargets.forEach((open) => { if (open.open) open.close() })
    const dialog = this.dialogTargets.find((candidate) => candidate.dataset.name === event.params.dialog)
    if (dialog) dialog.showModal()
  }

  close(event) { event.currentTarget.closest("dialog").close() }

  backdrop(event) { if (event.target.tagName === "DIALOG") event.target.close() }
}
