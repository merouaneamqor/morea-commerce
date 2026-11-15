import { Controller } from "@hotwired/stimulus"

// Find-my-size drawer: height/weight → shape → fit → recommendation.
// Answers stay in localStorage; nothing is posted to the server.
export default class extends Controller {
  static targets = [
    "shell", "panel", "scrim", "step", "height", "weight", "heightUnit", "weightUnit",
    "shape", "fit", "resultTitle", "resultBody", "resultSize", "resultReasons",
    "resultChart", "progress", "selectButton", "error"
  ]

  static values = {
    chart: Object,
    storageKey: { type: String, default: "morea-size-advisor" },
    labels: Object
  }

  static BODY_SHAPES = {
    slim: { chest: 0.95, waist: 0.91, hips: 0.96 },
    average: { chest: 1.0, waist: 1.0, hips: 1.0 },
    athletic: { chest: 1.04, waist: 0.93, hips: 1.01 },
    broad: { chest: 1.06, waist: 1.06, hips: 1.04 }
  }

  static PROFILES = {
    menswear: { chest_h: 0.50, chest_bmi: 1.9, chest_base: 6.0, waist_r: 0.86, hips_r: 0.97, length_r: 0.40, waist_bmi: 0.85 },
    womenswear: { chest_h: 0.48, chest_bmi: 1.45, chest_base: 3.5, waist_r: 0.77, hips_r: 1.07, length_r: 0.37, waist_bmi: 0.75 },
    unisex: { chest_h: 0.49, chest_bmi: 1.7, chest_base: 4.8, waist_r: 0.82, hips_r: 1.02, length_r: 0.385, waist_bmi: 0.8 }
  }

  static BASE_EASE = {
    tops: { chest: 10, waist: 11, hips: 8, length: 0 },
    bottoms: { chest: 0, waist: 3, hips: 5, length: 0 }
  }

  static FIT_PREFS = { fitted: -3, regular: 0, relaxed: 5 }
  static CUT_EASE = { slim: -3, regular: 0, relaxed: 3, oversized: 8 }
  static MEASURE_WEIGHTS = {
    tops: { chest: 1.0, waist: 0.5, hips: 0.4, length: 0.25 },
    bottoms: { chest: 0, waist: 1.0, hips: 0.95, length: 0.2 }
  }

  connect() {
    this.stepIndex = 0
    this.answers = this.loadAnswers()
    this.applyAnswersToForm()
    this.showStep(0)
    this.boundKey = this.onKey.bind(this)
  }

  disconnect() {
    document.removeEventListener("keydown", this.boundKey)
    document.body.classList.remove("overflow-hidden")
  }

  open(event) {
    event?.preventDefault()
    const shell = this.hasShellTarget ? this.shellTarget : this.element
    shell.classList.add("is-open")
    shell.setAttribute("aria-hidden", "false")
    document.body.classList.add("overflow-hidden")
    document.addEventListener("keydown", this.boundKey)
    this.showStep(this.answers.complete ? this.stepTargets.length - 1 : 0)
    if (this.answers.complete) this.renderResult()
    requestAnimationFrame(() => this.focusFirst())
  }

  close(event) {
    event?.preventDefault()
    const shell = this.hasShellTarget ? this.shellTarget : this.element
    shell.classList.remove("is-open")
    shell.setAttribute("aria-hidden", "true")
    document.body.classList.remove("overflow-hidden")
    document.removeEventListener("keydown", this.boundKey)
  }

  backdrop(event) {
    if (event.target === this.scrimTarget) this.close()
  }

  onKey(event) {
    if (event.key === "Escape") this.close()
  }

  next(event) {
    event?.preventDefault()
    if (!this.captureCurrentStep()) return
    this.showStep(Math.min(this.stepIndex + 1, this.stepTargets.length - 1))
    if (this.stepIndex === this.stepTargets.length - 1) this.renderResult()
  }

  back(event) {
    event?.preventDefault()
    this.clearError()
    this.showStep(Math.max(this.stepIndex - 1, 0))
  }

  chooseShape(event) {
    event.preventDefault()
    this.answers.bodyShape = event.currentTarget.dataset.value
    this.highlightChoices("shape", this.answers.bodyShape)
  }

  chooseFit(event) {
    event.preventDefault()
    this.answers.fitPreference = event.currentTarget.dataset.value
    this.highlightChoices("fit", this.answers.fitPreference)
  }

  toggleHeightUnit(event) {
    event.preventDefault()
    const next = this.answers.heightUnit === "cm" ? "ft" : "cm"
    const cm = this.heightCm()
    this.answers.heightUnit = next
    if (this.hasHeightUnitTarget) this.heightUnitTarget.textContent = next === "cm" ? "cm" : "ft in"
    if (cm > 0) {
      this.heightTarget.value = next === "cm" ? Math.round(cm) : this.cmToFtIn(cm)
    }
  }

  toggleWeightUnit(event) {
    event.preventDefault()
    const next = this.answers.weightUnit === "kg" ? "lb" : "kg"
    const kg = this.weightKg()
    this.answers.weightUnit = next
    if (this.hasWeightUnitTarget) this.weightUnitTarget.textContent = next
    if (kg > 0) {
      this.weightTarget.value = next === "kg" ? Math.round(kg) : Math.round(kg * 2.20462)
    }
  }

  selectOnPage(event) {
    event?.preventDefault()
    const size = this.recommendedSize
    if (!size) return
    const root = this.element.closest("[data-controller~='variant-picker']") || document
    const button = root.querySelector(`[data-variant-picker-target="sizeButton"][data-size="${CSS.escape(size)}"]`)
    button?.click()
    this.close()
  }

  showStep(index) {
    this.stepIndex = index
    this.stepTargets.forEach((step, i) => { step.hidden = i !== index })
    if (this.hasProgressTarget) {
      const total = Math.max(this.stepTargets.length - 1, 1)
      const current = Math.min(index + 1, total)
      this.progressTarget.textContent = this.label("step_of", { current, total })
        .replace("%{current}", current)
        .replace("%{total}", total)
    }
  }

  captureCurrentStep() {
    this.clearError()
    const step = this.stepTargets[this.stepIndex]
    const name = step?.dataset.step

    if (name === "measures") {
      const heightCm = this.heightCm()
      const weightKg = this.weightKg()
      if (!(heightCm >= 120 && heightCm <= 230)) {
        this.showError(this.label("height_invalid"))
        return false
      }
      if (!(weightKg >= 35 && weightKg <= 250)) {
        this.showError(this.label("weight_invalid"))
        return false
      }
      this.answers.heightCm = heightCm
      this.answers.weightKg = weightKg
      this.answers.heightUnit = this.answers.heightUnit || "cm"
      this.answers.weightUnit = this.answers.weightUnit || "kg"
    }

    if (name === "shape") {
      this.answers.bodyShape = this.answers.bodyShape || "average"
    }

    if (name === "fit") {
      this.answers.fitPreference = this.answers.fitPreference || "regular"
      this.answers.complete = true
      this.saveAnswers()
    }

    return true
  }

  renderResult() {
    const result = this.recommend()
    this.recommendedSize = result.size

    if (this.hasResultSizeTarget) {
      this.resultSizeTarget.textContent = result.size || "—"
    }

    if (this.hasResultTitleTarget) {
      if (result.verdict === "between") {
        this.resultTitleTarget.textContent = this.label("between_title")
          .replace("%{size}", result.size)
          .replace("%{other}", result.alternateSize)
      } else if (result.verdict === "best") {
        this.resultTitleTarget.textContent = this.label("best_title").replace("%{size}", result.size)
      } else {
        this.resultTitleTarget.textContent = this.label("none_title")
      }
    }

    if (this.hasResultBodyTarget) {
      this.resultBodyTarget.textContent = result.verdict === "none"
        ? this.label("none_body")
        : this.label("result_body")
    }

    if (this.hasResultReasonsTarget) {
      this.resultReasonsTarget.innerHTML = ""
      ;(result.reasons || []).forEach((reason) => {
        const li = document.createElement("li")
        li.className = "size-advisor__reason"
        const measure = this.label(`measure_${reason.measure}`)
        const note = this.label(`note_${reason.note}`)
        const delta = reason.delta
        const unit = this.answers.displayUnit === "in" ? "in" : "cm"
        const shown = unit === "in" ? (delta / 2.54).toFixed(1) : delta
        li.textContent = `${measure}: ${shown > 0 ? "+" : ""}${shown} ${unit} · ${note}`
        this.resultReasonsTarget.appendChild(li)
      })
    }

    if (this.hasResultChartTarget) {
      this.resultChartTarget.innerHTML = this.chartTableHtml(result.size)
    }

    if (this.hasSelectButtonTarget) {
      this.selectButtonTarget.disabled = !result.size
      this.selectButtonTarget.hidden = !result.size
    }
  }

  recommend() {
    const rows = this.chartValue?.rows || []
    if (!rows.length || !this.answers.heightCm || !this.answers.weightKg) {
      return { verdict: "none", size: null, alternateSize: null, reasons: [] }
    }

    const body = this.estimateBody()
    const target = this.garmentTarget(body)
    const scored = rows.map((row) => this.scoreRow(row, target)).sort((a, b) => a.distance - b.distance)
    const best = scored[0]
    const second = scored[1]
    const between = second && (second.distance - best.distance) < 3.5 && best.distance > 1.8

    return {
      verdict: between ? "between" : "best",
      size: best.size,
      alternateSize: between ? second.size : null,
      reasons: best.reasons,
      body,
      target
    }
  }

  estimateBody() {
    const height = this.answers.heightCm
    const weight = this.answers.weightKg
    const profileName = this.constructor.PROFILES[this.chartValue?.profile] ? this.chartValue.profile : "unisex"
    const profile = this.constructor.PROFILES[profileName]
    const shape = this.constructor.BODY_SHAPES[this.answers.bodyShape] || this.constructor.BODY_SHAPES.average
    const bmi = Math.min(40, Math.max(17, weight / ((height / 100) ** 2)))
    const bmiDelta = bmi - 22
    const softBmi = bmiDelta >= 0 ? Math.pow(bmiDelta, 0.92) : bmiDelta

    const chest = (height * profile.chest_h + softBmi * profile.chest_bmi + profile.chest_base) * shape.chest
    const waist = (
      height * profile.chest_h * profile.waist_r +
      softBmi * (profile.chest_bmi * profile.waist_r + profile.waist_bmi) +
      profile.chest_base * profile.waist_r
    ) * shape.waist
    const hips = (
      height * profile.chest_h * profile.hips_r +
      softBmi * profile.chest_bmi * profile.hips_r +
      profile.chest_base * profile.hips_r
    ) * shape.hips
    const length = height * profile.length_r

    return {
      chest: round1(chest),
      waist: round1(waist),
      hips: round1(hips),
      length: round1(length)
    }
  }

  garmentTarget(body) {
    const garment = this.constructor.BASE_EASE[this.chartValue?.garment] ? this.chartValue.garment : "tops"
    const base = this.constructor.BASE_EASE[garment]
    const fitBias = this.constructor.FIT_PREFS[this.answers.fitPreference] ?? 0
    const cutEase = this.constructor.CUT_EASE[this.chartValue?.cut] ?? 0
    const ease = fitBias + cutEase
    const target = {}
    Object.keys(body).forEach((key) => {
      const measureEase = key === "length" ? ease * 0.2 : ease
      target[key] = round1(body[key] + (base[key] || 0) + measureEase)
    })
    return target
  }

  scoreRow(row, target) {
    const garment = this.constructor.BASE_EASE[this.chartValue?.garment] ? this.chartValue.garment : "tops"
    const keys = garment === "bottoms" ? ["waist", "hips", "length"] : ["chest", "waist", "hips", "length"]
    const weights = this.constructor.MEASURE_WEIGHTS[garment]
    const reasons = []
    let total = 0
    let weightSum = 0

    keys.forEach((key) => {
      const garmentValue = row[key]
      if (garmentValue == null || garmentValue === "") return
      const weight = weights[key] || 0
      if (weight <= 0) return
      const delta = Number(garmentValue) - target[key]
      const distance = key === "length"
        ? (delta < 0 ? Math.abs(delta) * 1.4 : delta * 0.6)
        : (delta < 0 ? Math.abs(delta) * 1.65 : delta * 0.85)
      total += distance * weight
      weightSum += weight
      const threshold = key === "length" ? 2.5 : 2
      reasons.push({
        measure: key,
        delta: round1(delta),
        note: Math.abs(delta) < threshold ? "match" : delta < 0 ? "snug" : delta < 7 ? "easy" : "roomy"
      })
    })

    return {
      size: row.size,
      distance: weightSum === 0 ? 999 : total / weightSum,
      reasons
    }
  }

  chartTableHtml(activeSize) {
    const rows = this.chartValue?.rows || []
    if (!rows.length) return ""
    const keys = ["size", "chest", "waist", "hips", "length"]
    const head = keys.map((key) => `<th>${escapeHtml(this.label(key === "size" ? "size" : `measure_${key}`))}</th>`).join("")
    const body = rows.map((row) => {
      const active = row.size === activeSize ? " is-active" : ""
      const cells = keys.map((key) => `<td>${escapeHtml(String(row[key] ?? "—"))}</td>`).join("")
      return `<tr class="size-advisor__chart-row${active}">${cells}</tr>`
    }).join("")
    return `<table class="size-advisor__chart"><thead><tr>${head}</tr></thead><tbody>${body}</tbody></table>`
  }

  heightCm() {
    const raw = this.hasHeightTarget ? this.heightTarget.value.trim() : ""
    if (!raw) return 0
    if ((this.answers.heightUnit || "cm") === "ft") {
      const match = raw.match(/^(\d+)\s*['′]?\s*(\d+(?:\.\d+)?)?/)
      if (!match) return 0
      const feet = Number(match[1] || 0)
      const inches = Number(match[2] || 0)
      return (feet * 12 + inches) * 2.54
    }
    return Number(raw)
  }

  weightKg() {
    const raw = this.hasWeightTarget ? Number(this.weightTarget.value) : 0
    if (!raw) return 0
    return (this.answers.weightUnit || "kg") === "lb" ? raw / 2.20462 : raw
  }

  cmToFtIn(cm) {
    const total = cm / 2.54
    const feet = Math.floor(total / 12)
    const inches = Math.round(total % 12)
    return `${feet}'${inches}`
  }

  applyAnswersToForm() {
    this.answers.heightUnit = this.answers.heightUnit || "cm"
    this.answers.weightUnit = this.answers.weightUnit || "kg"
    if (this.hasHeightUnitTarget) this.heightUnitTarget.textContent = this.answers.heightUnit === "cm" ? "cm" : "ft in"
    if (this.hasWeightUnitTarget) this.weightUnitTarget.textContent = this.answers.weightUnit
    if (this.answers.heightCm && this.hasHeightTarget) {
      this.heightTarget.value = this.answers.heightUnit === "cm"
        ? Math.round(this.answers.heightCm)
        : this.cmToFtIn(this.answers.heightCm)
    }
    if (this.answers.weightKg && this.hasWeightTarget) {
      this.weightTarget.value = this.answers.weightUnit === "kg"
        ? Math.round(this.answers.weightKg)
        : Math.round(this.answers.weightKg * 2.20462)
    }
    this.highlightChoices("shape", this.answers.bodyShape || "average")
    this.highlightChoices("fit", this.answers.fitPreference || "regular")
    this.answers.bodyShape = this.answers.bodyShape || "average"
    this.answers.fitPreference = this.answers.fitPreference || "regular"
  }

  highlightChoices(kind, value) {
    const buttons = kind === "shape" ? this.shapeTargets : this.fitTargets
    buttons.forEach((button) => {
      const active = button.dataset.value === value
      button.classList.toggle("is-active", active)
      button.setAttribute("aria-pressed", String(active))
    })
  }

  loadAnswers() {
    try {
      return JSON.parse(localStorage.getItem(this.storageKeyValue) || "{}") || {}
    } catch (_error) {
      return {}
    }
  }

  saveAnswers() {
    try {
      localStorage.setItem(this.storageKeyValue, JSON.stringify({
        heightCm: this.answers.heightCm,
        weightKg: this.answers.weightKg,
        heightUnit: this.answers.heightUnit,
        weightUnit: this.answers.weightUnit,
        bodyShape: this.answers.bodyShape,
        fitPreference: this.answers.fitPreference,
        complete: true
      }))
    } catch (_error) {
      // Private browsing can block localStorage; the session still works.
    }
  }

  label(key, _vars = {}) {
    return (this.labelsValue && this.labelsValue[key]) || key
  }

  showError(message) {
    if (!this.hasErrorTarget) return
    this.errorTarget.textContent = message
    this.errorTarget.hidden = false
  }

  clearError() {
    if (!this.hasErrorTarget) return
    this.errorTarget.textContent = ""
    this.errorTarget.hidden = true
  }

  focusFirst() {
    const step = this.stepTargets[this.stepIndex]
    step?.querySelector("input, button")?.focus()
  }
}

function round1(value) {
  return Math.round(value * 10) / 10
}

function escapeHtml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
}
