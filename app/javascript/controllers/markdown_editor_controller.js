import { Controller } from "@hotwired/stimulus"

// GitHub-style Write / Preview tabs for a Markdown textarea. Preview is rendered
// server-side so it matches the storefront exactly.
export default class extends Controller {
  static targets = ["input", "output", "writeTab", "previewTab"]
  static values = { url: String }

  write() {
    this.inputTarget.hidden = false
    this.outputTarget.hidden = true
    this.#activate(this.writeTabTarget)
    this.inputTarget.focus()
  }

  async preview() {
    this.#activate(this.previewTabTarget)
    this.outputTarget.style.minHeight = `${this.inputTarget.offsetHeight}px`
    this.inputTarget.hidden = true
    this.outputTarget.hidden = false
    this.outputTarget.textContent = "Loading preview…"

    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/x-www-form-urlencoded",
          "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content || ""
        },
        body: new URLSearchParams({ body: this.inputTarget.value })
      })
      if (!response.ok) throw new Error(response.status)
      this.outputTarget.innerHTML = await response.text()
    } catch {
      this.outputTarget.textContent = "Preview unavailable."
    }
  }

  #activate(tab) {
    for (const t of [this.writeTabTarget, this.previewTabTarget]) t.classList.toggle("is-active", t === tab)
  }
}
