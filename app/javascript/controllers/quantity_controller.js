import { Controller } from "@hotwired/stimulus"

// − / + stepper around a quantity input
export default class extends Controller {
  static targets = ["input"]
  static values = { min: { type: Number, default: 1 }, max: { type: Number, default: 10 } }

  decrement() {
    this.set(this.current - 1)
  }

  increment() {
    this.set(this.current + 1)
  }

  get current() {
    return parseInt(this.inputTarget.value, 10) || this.minValue
  }

  set(value) {
    this.inputTarget.value = Math.min(this.maxValue, Math.max(this.minValue, value))
  }
}
