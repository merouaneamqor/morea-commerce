import { Controller } from "@hotwired/stimulus"

// Searchable city list, neighborhood options when needed, live shipping totals
export default class extends Controller {
  static targets = [
    "city",
    "cityList",
    "combobox",
    "district",
    "districtField",
    "districtHelp",
    "cityField",
    "shipping",
    "shippingInput",
    "total",
    "mobileTotal",
    "bagPreview",
    "submitLabel",
    "stickyLabel"
  ]
  static values = {
    cities: Array,
    districts: Object,
    rates: Object,
    subtotal: Number,
    discount: { type: Number, default: 0 },
    freeThreshold: Number,
    currency: String,
    freeLabel: String,
    pendingLabel: String,
    confirmTemplate: String,
    chooseDistrict: String,
    noMatch: String,
    locale: { type: String, default: "fr-MA" }
  }

  connect() {
    this.activeIndex = -1
    this.lastQuery = this.hasCityTarget ? this.cityTarget.value : ""
    this.update()
    this.catchAutofill()
  }

  disconnect() {
    if (this.autofillTimer) window.clearInterval(this.autofillTimer)
  }

  // Browsers often fill address-level2 without a reliable input event.
  catchAutofill() {
    if (!this.hasCityTarget) return

    this.autofillTimer = window.setInterval(() => {
      const value = this.cityTarget.value.trim()
      if (!value || value === this.lastQuery) return

      const exact = this.citiesValue.find((city) => this.normalize(city) === this.normalize(value))
      if (exact) {
        this.onCityChange()
        return
      }

      try {
        if (this.cityTarget.matches(":-webkit-autofill")) this.onCityChange()
      } catch (_) {
        // :webkit-autofill matching can throw in some engines
      }
    }, 250)

    window.setTimeout(() => {
      if (this.autofillTimer) window.clearInterval(this.autofillTimer)
      this.autofillTimer = null
    }, 4000)
  }

  onCityInput() {
    if (!this.hasCityTarget) return
    this.cityTarget.setCustomValidity("")
    this.lastQuery = this.cityTarget.value
    this.filterCities()
  }

  onCityChange() {
    if (!this.hasCityTarget) return
    this.cityTarget.setCustomValidity("")
    this.lastQuery = this.cityTarget.value
    this.commitTypedCity({ force: true })
    this.closeCities()
  }

  onAutofillAnimation(event) {
    if (event.animationName !== "checkout-autofill") return
    this.onCityChange()
  }

  validateCity(event) {
    if (!this.hasCitiesValue || this.citiesValue.length === 0) return

    this.commitTypedCity({ force: true })
    if (this.cityValue()) return

    event.preventDefault()
    if (this.hasCityTarget) {
      this.cityTarget.setCustomValidity(this.pendingLabelValue)
      this.cityTarget.reportValidity()
      this.cityTarget.focus()
    }
  }

  update() {
    this.refreshDistricts()
    this.refreshTotals()
  }

  filterCities() {
    if (!this.hasCityTarget || !this.hasCityListTarget) return

    const matches = this.rankCities(this.cityTarget.value)
    this.renderCityList(matches)
    this.openCities()
  }

  openCities() {
    if (!this.hasCityListTarget || !this.hasCityTarget) return
    if (this.cityListTarget.hidden && this.cityTarget.value.trim().length === 0) {
      this.renderCityList(this.citiesValue.slice(0, 12))
    }
    this.cityListTarget.hidden = false
    this.cityTarget.setAttribute("aria-expanded", "true")
  }

  closeCities() {
    if (!this.hasCityListTarget || !this.hasCityTarget) return
    this.cityListTarget.hidden = true
    this.cityTarget.setAttribute("aria-expanded", "false")
    this.activeIndex = -1
  }

  selectCity(event) {
    event.preventDefault()
    const city = event.currentTarget.dataset.city
    this.applyCity(city)
    this.closeCities()
  }

  onCityKeydown(event) {
    if (!this.hasCityListTarget || this.cityListTarget.hidden) {
      if (event.key === "ArrowDown") {
        event.preventDefault()
        this.filterCities()
      }
      return
    }

    const options = [...this.cityListTarget.querySelectorAll("[data-city]")]
    if (event.key === "ArrowDown") {
      event.preventDefault()
      this.activeIndex = Math.min(this.activeIndex + 1, options.length - 1)
      this.highlightOption(options)
    } else if (event.key === "ArrowUp") {
      event.preventDefault()
      this.activeIndex = Math.max(this.activeIndex - 1, 0)
      this.highlightOption(options)
    } else if (event.key === "Enter") {
      event.preventDefault()
      if (this.activeIndex >= 0 && options[this.activeIndex]) {
        this.applyCity(options[this.activeIndex].dataset.city)
        this.closeCities()
      } else {
        this.commitTypedCity({ force: true })
        this.closeCities()
      }
    } else if (event.key === "Escape") {
      this.closeCities()
    }
  }

  onCityBlur() {
    window.setTimeout(() => {
      this.commitTypedCity({ force: true })
      this.closeCities()
    }, 150)
  }

  commitTypedCity({ force = false } = {}) {
    if (!this.hasCityTarget) return
    const typed = this.cityTarget.value.trim()
    if (!typed) {
      this.applyCity("")
      return
    }

    const ranked = this.rankCities(typed)
    if (ranked.length === 0) return

    const best = ranked[0]
    const query = this.normalize(typed)
    const candidate = this.normalize(best)
    const score = this.fuzzyScore(query, candidate)

    if (
      candidate === query ||
      candidate.startsWith(query) ||
      (force && score != null && (query.length >= 3 || score >= 8000)) ||
      (!force && score != null && score >= 8000)
    ) {
      this.applyCity(best)
    }
  }

  applyCity(city) {
    if (this.hasCityTarget) {
      this.cityTarget.value = city
      this.lastQuery = city
    }
    this.update()
  }

  rankCities(rawQuery) {
    const query = this.normalize(rawQuery)
    if (!query) return this.citiesValue.slice(0, 12)

    const scored = []
    for (const city of this.citiesValue) {
      const score = this.fuzzyScore(query, this.normalize(city))
      if (score != null) scored.push({ city, score })
    }

    scored.sort((a, b) => b.score - a.score || a.city.localeCompare(b.city))
    return scored.slice(0, 12).map((entry) => entry.city)
  }

  // Higher is better. null = no match.
  fuzzyScore(query, candidate) {
    if (!query || !candidate) return null
    if (candidate === query) return 10000
    if (candidate.startsWith(query)) return 9000 - Math.min(candidate.length, 200)

    const index = candidate.indexOf(query)
    if (index >= 0) return 8000 - index * 15 - Math.min(candidate.length, 200)

    const words = candidate.split(/[^a-z0-9]+/).filter(Boolean)
    if (words.some((word) => word.startsWith(query))) return 7800
    if (words.some((word) => word.includes(query))) return 7600

    const subsequence = this.subsequenceScore(query, candidate)
    if (subsequence != null) return 5000 + subsequence

    if (query.length >= 3) {
      const maxDist = Math.min(3, Math.floor(query.length / 3) + 1)
      const prefix = candidate.slice(0, Math.min(candidate.length, query.length + maxDist))
      const distance = Math.min(
        this.levenshtein(query, candidate),
        this.levenshtein(query, prefix)
      )
      if (distance <= maxDist) return 3000 - distance * 120
    }

    return null
  }

  subsequenceScore(query, candidate) {
    let qi = 0
    let gaps = 0
    let last = -1

    for (let i = 0; i < candidate.length && qi < query.length; i += 1) {
      if (candidate[i] !== query[qi]) continue
      if (last >= 0) gaps += i - last - 1
      last = i
      qi += 1
    }

    if (qi < query.length) return null
    // Prefer tight subsequences (e.g. "rbt" in "rabat" over sparse matches)
    return Math.max(0, 400 - gaps * 12 - (candidate.length - query.length))
  }

  levenshtein(a, b) {
    if (a === b) return 0
    if (a.length === 0) return b.length
    if (b.length === 0) return a.length

    const rows = a.length + 1
    const cols = b.length + 1
    const matrix = new Array(rows)
    for (let i = 0; i < rows; i += 1) {
      matrix[i] = new Array(cols)
      matrix[i][0] = i
    }
    for (let j = 0; j < cols; j += 1) matrix[0][j] = j

    for (let i = 1; i < rows; i += 1) {
      for (let j = 1; j < cols; j += 1) {
        const cost = a[i - 1] === b[j - 1] ? 0 : 1
        matrix[i][j] = Math.min(
          matrix[i - 1][j] + 1,
          matrix[i][j - 1] + 1,
          matrix[i - 1][j - 1] + cost
        )
      }
    }

    return matrix[a.length][b.length]
  }

  renderCityList(matches) {
    this.cityListTarget.replaceChildren()
    this.activeIndex = -1

    if (matches.length === 0) {
      const empty = document.createElement("li")
      empty.className = "checkout-combobox__empty"
      empty.textContent = this.noMatchValue
      this.cityListTarget.appendChild(empty)
      return
    }

    matches.forEach((city) => {
      const option = document.createElement("li")
      option.setAttribute("role", "option")
      option.dataset.city = city
      option.dataset.action = "mousedown->checkout-city#selectCity"
      option.className = "checkout-combobox__option"
      option.textContent = city
      this.cityListTarget.appendChild(option)
    })
  }

  highlightOption(options) {
    options.forEach((option, index) => {
      option.classList.toggle("is-active", index === this.activeIndex)
    })
  }

  refreshDistricts() {
    if (!this.hasDistrictTarget || !this.hasDistrictFieldTarget) return

    const city = this.cityValue()
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

    if (this.hasCityFieldTarget) {
      this.cityFieldTarget.classList.toggle("sm:col-span-2", !required)
    }
  }

  refreshTotals() {
    const city = this.cityValue()
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
    const totalText = this.formatMoney(total)
    const confirmText = this.confirmTemplateValue.replace("%{total}", totalText)

    if (this.hasShippingTarget) this.shippingTarget.textContent = shippingText
    if (this.hasShippingInputTarget && shipping != null) {
      this.shippingInputTarget.value = String(Math.round(shipping / 100))
    }
    if (this.hasTotalTarget) this.totalTarget.textContent = totalText
    if (this.hasMobileTotalTarget) this.mobileTotalTarget.textContent = totalText
    if (this.hasBagPreviewTarget) this.bagPreviewTarget.textContent = totalText
    if (this.hasSubmitLabelTarget) this.submitLabelTarget.textContent = confirmText
    if (this.hasStickyLabelTarget) this.stickyLabelTarget.textContent = confirmText
  }

  cityValue() {
    if (!this.hasCityTarget) return ""
    const typed = this.cityTarget.value.trim()
    if (!typed) return ""

    const exact = this.citiesValue.find((city) => this.normalize(city) === this.normalize(typed))
    return exact || ""
  }

  normalize(value) {
    return value.toString().normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase().trim()
  }

  formatMoney(cents) {
    const amount = Math.round(Number(cents) / 100).toLocaleString(this.localeValue)
    return `${amount} ${this.currencyValue}`
  }
}
