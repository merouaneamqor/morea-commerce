import { Controller } from "@hotwired/stimulus"

// Suggests the Sendit quartiers of the chosen city in the quartier field
export default class extends Controller {
  static targets = ["city", "district", "options"]
  static values = { districts: Object }

  connect() {
    this.update()
  }

  update() {
    const areas = this.districtsValue[this.cityTarget.value] || []
    this.optionsTarget.replaceChildren(...areas.map((area) => {
      const option = document.createElement("option")
      option.value = area
      return option
    }))
  }
}
