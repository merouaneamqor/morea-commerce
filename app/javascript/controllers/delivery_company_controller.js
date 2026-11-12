import { Controller } from "@hotwired/stimulus"

// New-order window: the cities and delivery prices come from the delivery company that is chosen. Choosing another company
// swaps the city list (and the districts and prices) of the city picker, empties the city and recomputes the delivery fee.
export default class extends Controller {
  static values = { catalogs: Object }

  change(event) {
    const catalog = this.catalogsValue[event.target.value] || { cities: [], districts: {}, rates: {} }
    this.element.setAttribute("data-checkout-city-cities-value", JSON.stringify(catalog.cities || []))
    this.element.setAttribute("data-checkout-city-districts-value", JSON.stringify(catalog.districts || {}))
    this.element.setAttribute("data-checkout-city-rates-value", JSON.stringify(catalog.rates || {}))

    const picker = this.application.getControllerForElementAndIdentifier(this.element, "checkout-city")
    if (picker) {
      picker.closeCities()
      picker.applyCity("")
    }
    this.element.dispatchEvent(new Event("change", { bubbles: true }))
  }
}
