import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["compact", "full", "countrySelect", "maCountry"]

  connect() {
    this.element.addEventListener("checkout-recall:foreign-phone", () => this.expand())
  }

  expand() {
    this.compactTargets.forEach((el) => {
      el.hidden = true
    })
    if (this.hasFullTarget) this.fullTarget.hidden = false
    if (this.hasMaCountryTarget) this.maCountryTarget.disabled = true
    if (this.hasCountrySelectTarget) {
      this.countrySelectTarget.disabled = false
      if (this.hasMaCountryTarget && this.maCountryTarget.value) {
        this.countrySelectTarget.value = this.maCountryTarget.value
      }
    }
  }
}
