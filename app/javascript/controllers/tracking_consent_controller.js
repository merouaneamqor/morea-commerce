import { Controller } from "@hotwired/stimulus"

// Records CNDP-required consent before marketing pixels (Meta, TikTok) load.
export default class extends Controller {
  static values = { url: String }

  async accept() {
    await this.post("grant")
    window.location.reload()
  }

  async deny() {
    await this.post("deny")
    this.element.remove()
  }

  async post(status) {
    const token = document.querySelector('meta[name="csrf-token"]')?.content
    await fetch(this.urlValue, {
      method: "POST",
      headers: {
        "X-CSRF-Token": token,
        "Content-Type": "application/x-www-form-urlencoded",
        Accept: "application/json"
      },
      body: new URLSearchParams({ status }),
      credentials: "same-origin"
    })
  }
}
