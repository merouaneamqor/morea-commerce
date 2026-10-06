import { Controller } from "@hotwired/stimulus"

// Fills neighborhood options when the city needs one, and updates shipping from cached rates
export default class extends Controller {
  static targets = [
    "city",
    "district",
    "districtField",
    "districtHelp",
    "shipping",
    "total",
    "mobileTotal",
    "submitLabel"
  ]
  static values = {
    districts: Object,
    rates: Object,
    subtotal: Number,
    discount: { type: Number, default: 0 },
    freeThreshold: Number,
    currency: String,
    freeLabel: String,
    pendingLabel: String,
    confirmTemplate: String,
    chooseDistrict: String
  }

  connect() {
    this.update()
  }

  update() {
    this.refreshDistricts()
    this.refreshTotals()
  }

  refreshDistricts() {
    if (!this.hasDistrictTarget || !this.hasDistrictFieldTarget) return

    const city = this.cityTarget.value
    const areas = this.districtsValue[city] || []
    const required = areas.length > 1
    const previous = this.districtTarget.value

    this.districtTarget.replaceChildren()
    const blank = document.createElement("option")
    blank.value = ""
    blank.textContent = this.chooseDistrictValue
    this.districtTarget.appendChild(blank)

    areas.forEach((area) => {
      const option = document.createElement("option")
      option.value = area
      option.textContent = area
      if (area === previous) option.selected = true
      this.districtTarget.appendChild(option)
    })

    this.districtFieldTarget.hidden = !required
    this.districtTarget.required = required
    this.districtTarget.disabled = !required
    if (!required) this.districtTarget.value = ""
    if (this.hasDistrictHelpTarget) this.districtHelpTarget.hidden = !required
  }

  refreshTotals() {
    const city = this.hasCityTarget ? this.cityTarget.value : ""
    const net = Math.max(this.subtotalValue - this.discountValue, 0)
    let shipping = 0

    if (this.freeThresholdValue > 0 && net >= this.freeThresholdValue) {
      shipping = 0
    } else if (city && this.ratesValue[city] != null) {
      shipping = Number(this.ratesValue[city]) || 0
    } else if (!city) {
      shipping = null
    }

    const total = shipping == null ? net : net + shipping
    const shippingText = shipping == null
      ? this.pendingLabelValue
      : (shipping === 0 ? this.freeLabelValue : this.formatMoney(shipping))

    if (this.hasShippingTarget) this.shippingTarget.textContent = shippingText
    if (this.hasTotalTarget) this.totalTarget.textContent = this.formatMoney(total)
    if (this.hasMobileTotalTarget) this.mobileTotalTarget.textContent = this.formatMoney(total)
    if (this.hasSubmitLabelTarget) {
      this.submitLabelTarget.textContent = this.confirmTemplateValue.replace("%{total}", this.formatMoney(total))
    }
  }

  formatMoney(cents) {
    const amount = Math.round(Number(cents) / 100).toLocaleString("fr-MA")
    return `${amount} ${this.currencyValue}`
  }
}
