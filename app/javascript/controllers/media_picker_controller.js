import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog", "title", "choice", "count", "search"]

  open(event) {
    this.opener = event.currentTarget
    this.owner = this.opener.closest("[data-media-picker-owner]")
    this.field = this.owner.querySelector("[data-media-picker-selection]")
    this.selected = JSON.parse(this.field.value || "[]").map(String)
    this.titleTarget.textContent = `Select images · ${this.opener.dataset.name || "Variant"}`
    this.searchTarget.value = ""
    this.filter()
    this.render()
    this.dialogTarget.showModal()
  }

  toggle(event) {
    const id = event.currentTarget.dataset.blobId
    this.selected = this.selected.includes(id) ? this.selected.filter(value => value !== id) : [...this.selected, id]
    this.render()
  }

  makeMain(event) {
    const id = event.currentTarget.dataset.blobId
    this.selected = [id, ...this.selected.filter(value => value !== id)]
    this.render()
  }

  render() {
    this.choiceTargets.forEach(choice => {
      const index = this.selected.indexOf(choice.dataset.blobId)
      const button = choice.querySelector("[data-choice-toggle]")
      button.setAttribute("aria-pressed", String(index >= 0))
      choice.classList.toggle("is-selected", index >= 0)
      choice.querySelector("[data-choice-badge]").textContent = index < 0 ? "" : index === 0 ? "Main" : String(index + 1)
      choice.querySelector("[data-choice-main]").hidden = index <= 0
    })
    this.countTarget.textContent = `${this.selected.length} selected`
  }

  filter() {
    const query = this.searchTarget.value.toLowerCase().trim()
    this.choiceTargets.forEach(choice => { choice.hidden = !choice.dataset.filename.toLowerCase().includes(query) })
  }

  done() {
    this.field.value = JSON.stringify(this.selected)
    this.field.disabled = false
    const preview = this.owner.querySelector("[data-media-picker-preview]")
    const choice = this.choiceTargets.find(choice => choice.dataset.blobId === this.selected[0])
    preview.replaceChildren()
    if (choice) {
      const image = choice.querySelector("img").cloneNode(true)
      image.alt = "Selected variant image"
      preview.append(image)
    } else preview.textContent = "+"
    const status = this.owner.querySelector("[data-media-picker-status]")
    if (status) status.textContent = this.selected.length ? `${this.selected.length} selected · Save to apply` : "Use color or product photos · Save to apply"
    this.close()
  }

  close() {
    this.dialogTarget.close()
    this.opener?.focus()
  }
}
