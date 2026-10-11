import { Controller } from "@hotwired/stimulus"

// Prefill checkout from localStorage (per store) without overwriting user input.
export default class extends Controller {
  static values = { store: String }

  connect() {
    this.storageKey = `morea_delivery_${this.storeValue}`
    this.restore()
    this.element.addEventListener("input", this.debouncedSave)
    this.element.addEventListener("change", this.debouncedSave)
    this.element.addEventListener("submit", this.save)
  }

  disconnect() {
    this.element.removeEventListener("input", this.debouncedSave)
    this.element.removeEventListener("change", this.debouncedSave)
    this.element.removeEventListener("submit", this.save)
    clearTimeout(this.saveTimer)
  }

  debouncedSave = () => {
    clearTimeout(this.saveTimer)
    this.saveTimer = setTimeout(() => this.save(), 400)
  }

  save = () => {
    const data = {}
    this.element.querySelectorAll("[name^='checkout[']").forEach((input) => {
      const match = input.name.match(/^checkout\[(\w+)\]$/)
      if (!match) return
      const key = match[1]
      if (!["name", "phone", "phone_country", "city", "district", "address"].includes(key)) return
      if (input.type === "checkbox" || input.type === "radio") return
      data[key] = input.value
    })
    try {
      localStorage.setItem(this.storageKey, JSON.stringify(data))
    } catch {
      // Private mode or quota — ignore
    }
  }

  restore() {
    let raw
    try {
      raw = localStorage.getItem(this.storageKey)
    } catch {
      return
    }
    if (!raw) return

    let data
    try {
      data = JSON.parse(raw)
    } catch {
      return
    }

    Object.entries(data).forEach(([key, value]) => {
      if (!value) return
      const input = this.element.querySelector(`[name='checkout[${key}]']`)
      if (input && !input.value) input.value = value
    })

    if (data.phone_country && data.phone_country !== "MA") {
      this.element.dispatchEvent(new CustomEvent("checkout-recall:foreign-phone", { bubbles: true }))
    }
  }
}
