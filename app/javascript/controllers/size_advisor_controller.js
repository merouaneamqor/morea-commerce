import { Controller } from "@hotwired/stimulus"

// Find-my-size drawer: height/weight → shape → fit → recommendation.
// Size guide opens the same shell with a dedicated chart view.
// Answers stay in localStorage; nothing is posted to the server.
export default class extends Controller {
  static targets = [
    "shell", "panel", "scrim", "step", "height", "weight", "heightUnit", "weightUnit",
    "shape", "fit", "resultTitle", "resultBody", "resultSize", "resultReasons",
    "resultChart", "progress", "selectButton", "editButton", "error",
    "eyebrow", "title", "guidePanel", "guideBody", "guideTabs", "guidePartTitle", "guideChart", "guideNote"
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
    this.guidePartIndex = 0
    this.answers = this.loadAnswers()
    this.applyAnswersToForm()
    this.showStep(0)
    this.boundKey = this.onKey.bind(this)
  }

  disconnect() {
    document.removeEventListener("keydown", this.boundKey)
    document.body.classList.remove("overflow-hidden")
    document.documentElement.classList.remove("size-advisor-open")
  }

  open(event) {
    event?.preventDefault()
    this.guideOnly = false
    this.setAdvisorChrome()
    this.hideGuidePanel()
    this.openShell()
    this.showStep(this.answers.complete ? this.stepTargets.length - 1 : 0)
    if (this.answers.complete) this.renderResult()
    requestAnimationFrame(() => this.focusFirst())
  }

  // Size chart only — no height/weight questionnaire.
  openGuide(event) {
    event?.preventDefault()
    this.guideOnly = true
    this.setGuideChrome()
    this.openShell()
    this.renderGuide()
    requestAnimationFrame(() => {
      const focusable = this.hasGuideTabsTarget && !this.guideTabsTarget.hidden
        ? this.guideTabsTarget.querySelector("button")
        : this.guidePanelTarget?.querySelector("button")
      focusable?.focus()
    })
  }

  openShell() {
    const shell = this.hasShellTarget ? this.shellTarget : this.element
    shell.classList.toggle("size-advisor--guide", Boolean(this.guideOnly))
    shell.classList.add("is-open")
    shell.setAttribute("aria-hidden", "false")
    document.body.classList.add("overflow-hidden")
    document.documentElement.classList.add("size-advisor-open")
    document.addEventListener("keydown", this.boundKey)
  }

  close(event) {
    event?.preventDefault()
    event?.stopPropagation?.()
    const shell = this.hasShellTarget ? this.shellTarget : this.element
    shell.classList.remove("is-open", "size-advisor--guide")
    shell.setAttribute("aria-hidden", "true")
    document.body.classList.remove("overflow-hidden")
    document.documentElement.classList.remove("size-advisor-open")
    document.removeEventListener("keydown", this.boundKey)
  }

  backdrop(event) {
    if (event.target === this.scrimTarget) this.close(event)
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

  chooseGuidePart(event) {
    const button = event.target.closest("[data-part-index]")
    if (!button || !this.hasGuideTabsTarget || !this.guideTabsTarget.contains(button)) return

    event.preventDefault()
    const index = Number(button.dataset.partIndex || 0)
    if (!Number.isFinite(index) || index === this.guidePartIndex) return
    this.guidePartIndex = index
    this.renderGuidePart()
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
    this.hideGuidePanel()
    this.stepTargets.forEach((step, i) => { step.hidden = i !== index })
    if (this.hasProgressTarget) {
      const total = Math.max(this.stepTargets.length - 1, 1)
      const current = Math.min(index + 1, total)
      this.progressTarget.hidden = false
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

  renderGuide() {
    this.stepTargets.forEach((step) => { step.hidden = true })
    if (this.hasProgressTarget) {
      this.progressTarget.textContent = ""
      this.progressTarget.hidden = true
    }
    if (this.hasGuidePanelTarget) this.guidePanelTarget.hidden = false
    if (this.hasGuideBodyTarget) this.guideBodyTarget.textContent = this.label("guide_body")
    if (this.hasGuideNoteTarget) {
      const basis = this.chartValue?.basis === "flat" ? "flat" : "circumference"
      this.guideNoteTarget.textContent = this.label(basis === "flat" ? "guide_note_flat" : "guide_note_circumference")
    }

    const parts = this.displayParts()
    this.guidePartIndex = Math.min(this.guidePartIndex, Math.max(parts.length - 1, 0))
    this.renderGuideTabs(parts)
    this.renderGuidePart()
  }

  renderGuideTabs(parts) {
    if (!this.hasGuideTabsTarget) return
    const showTabs = parts.length > 1
    this.guideTabsTarget.hidden = !showTabs
    if (!showTabs) {
      this.guideTabsTarget.innerHTML = ""
      return
    }

    this.guideTabsTarget.innerHTML = parts.map((part, index) => {
      const active = index === this.guidePartIndex ? " is-active" : ""
      const pressed = index === this.guidePartIndex
      const label = this.partLabel(part, index, parts.length)
      return `<button type="button" class="size-advisor__tab${active}" role="tab" aria-selected="${pressed}" data-part-index="${index}">${escapeHtml(label)}</button>`
    }).join("")
  }

  renderGuidePart() {
    const parts = this.displayParts()
    const part = parts[this.guidePartIndex] || parts[0]
    if (this.hasGuideTabsTarget && !this.guideTabsTarget.hidden) {
      this.guideTabsTarget.querySelectorAll("[data-part-index]").forEach((button) => {
        const active = Number(button.dataset.partIndex) === this.guidePartIndex
        button.classList.toggle("is-active", active)
        button.setAttribute("aria-selected", String(active))
      })
    }
    if (this.hasGuidePartTitleTarget) {
      const showTitle = parts.length > 1 && part
      this.guidePartTitleTarget.hidden = !showTitle
      this.guidePartTitleTarget.textContent = showTitle ? this.partLabel(part, this.guidePartIndex, parts.length) : ""
    }
    if (this.hasGuideChartTarget) {
      this.guideChartTarget.innerHTML = part
        ? this.chartTableHtml(null, part.rows, part.garment)
        : ""
    }
  }

  renderResult() {
    this.guideOnly = false
    this.hideGuidePanel()
    if (this.hasEditButtonTarget) this.editButtonTarget.hidden = false

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
      const part = this.advisorParts()[0]
      this.resultChartTarget.innerHTML = this.chartTableHtml(
        result.size,
        part?.rows || this.chartValue?.rows || [],
        part?.garment || this.chartValue?.garment
      )
    }

    if (this.hasSelectButtonTarget) {
      this.selectButtonTarget.disabled = !result.size
      this.selectButtonTarget.hidden = !result.size
    }
  }

  recommend() {
    const parts = this.advisorParts()
    if (!parts.length || !this.answers.heightCm || !this.answers.weightKg) {
      return { verdict: "none", size: null, alternateSize: null, reasons: [] }
    }

    const results = parts.map((part) => this.recommendForPart(part))
    return this.mergeRecommendations(results)
  }

  recommendForPart(part) {
    const rows = part.rows || []
    if (!rows.length) {
      return { verdict: "none", size: null, alternateSize: null, reasons: [], rank: -1 }
    }

    const body = this.estimateBody()
    const target = this.garmentTarget(body, part.garment)
    const scored = rows.map((row) => this.scoreRow(row, target, part.garment)).sort((a, b) => a.distance - b.distance)
    const best = scored[0]
    const second = scored[1]
    const between = second && (second.distance - best.distance) < 3.5 && best.distance > 1.8

    return {
      verdict: between ? "between" : "best",
      size: best.size,
      alternateSize: between ? second.size : null,
      reasons: best.reasons,
      rank: this.sizeRank(best.size)
    }
  }

  mergeRecommendations(results) {
    const usable = results.filter((result) => result.size)
    if (!usable.length) return results[0] || { verdict: "none", size: null, alternateSize: null, reasons: [] }
    if (usable.length === 1) return usable[0]

    usable.sort((a, b) => b.rank - a.rank)
    const largest = usable[0]
    const sizes = new Set(usable.map((result) => result.size))
    if (sizes.size === 1) return largest

    const next = usable.find((result) => result.size !== largest.size)
    return {
      verdict: "between",
      size: largest.size,
      alternateSize: next?.size || null,
      reasons: largest.reasons
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

  garmentTarget(body, garmentName) {
    const garment = this.constructor.BASE_EASE[garmentName] ? garmentName : "tops"
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

  scoreRow(row, target, garmentName) {
    const garment = this.constructor.BASE_EASE[garmentName] ? garmentName : "tops"
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

  chartTableHtml(activeSize, rows = null, garmentName = null) {
    const chartRows = rows || this.chartValue?.rows || []
    if (!chartRows.length) return ""
    const garment = this.constructor.BASE_EASE[garmentName] ? garmentName : (this.chartValue?.garment || "tops")
    const candidateKeys = garment === "bottoms"
      ? ["size", "waist", "hips", "length"]
      : ["size", "chest", "waist", "hips", "length"]
    const keys = candidateKeys.filter((key) => {
      if (key === "size") return true
      return chartRows.some((row) => row[key] != null && row[key] !== "")
    })
    const head = keys.map((key) => `<th>${escapeHtml(this.measureHeading(key, garment))}</th>`).join("")
    const body = chartRows.map((row) => {
      const active = row.size === activeSize ? " is-active" : ""
      const cells = keys.map((key) => {
        const value = row[key]
        const shown = value == null || value === "" ? "—" : formatMeasure(value)
        return `<td>${escapeHtml(String(shown))}</td>`
      }).join("")
      return `<tr class="size-advisor__chart-row${active}">${cells}</tr>`
    }).join("")
    return `<table class="size-advisor__chart"><thead><tr>${head}</tr></thead><tbody>${body}</tbody></table>`
  }

  measureHeading(key, garment) {
    if (key === "size") return this.label("size")
    if (key === "waist" && garment === "tops") return this.label("measure_hem")
    return this.label(`measure_${key}`)
  }

  displayParts() {
    const parts = Array.isArray(this.chartValue?.parts) ? this.chartValue.parts : []
    if (parts.length) {
      return parts.map((part, index) => ({
        key: part.key || `part-${index}`,
        label: part.label || "",
        garment: part.garment || "tops",
        rows: part.rows || []
      }))
    }
    return [ {
      key: "primary",
      label: "",
      garment: this.chartValue?.garment || "tops",
      rows: this.chartValue?.rows || []
    } ]
  }

  partLabel(part, index, total) {
    if (!part) return ""
    const key = String(part.key || "").toLowerCase()
    const garment = String(part.garment || "").toLowerCase()
    if (key === "bottom" || garment === "bottoms") return this.label("part_bottom")
    if (key === "top" || garment === "tops") return this.label("part_top")
    const raw = String(part.label || "").trim()
    if (raw && !raw.includes("/") && raw.length <= 24) return raw
    return this.defaultPartLabel(garment, index, total) || raw || this.label("part_top")
  }

  advisorParts() {
    const parts = Array.isArray(this.chartValue?.advisor_parts) ? this.chartValue.advisor_parts : []
    if (parts.length) {
      return parts.map((part) => ({
        key: part.key,
        label: part.label,
        garment: part.garment || "tops",
        rows: part.rows || []
      }))
    }
    return [ {
      key: "primary",
      garment: this.chartValue?.garment || "tops",
      rows: this.chartValue?.rows || []
    } ]
  }

  defaultPartLabel(garment, index, total) {
    if (total < 2) return ""
    if (garment === "bottoms") return this.label("part_bottom")
    if (garment === "tops") return this.label("part_top")
    return this.label("part_top")
  }

  sizeRank(size) {
    const order = ["XXS", "XS", "S", "M", "L", "XL", "XXL", "3XL", "4XL"]
    const index = order.indexOf(String(size || "").toUpperCase())
    return index >= 0 ? index : 0
  }

  setGuideChrome() {
    if (this.hasEyebrowTarget) this.eyebrowTarget.textContent = this.label("guide_eyebrow")
    if (this.hasTitleTarget) this.titleTarget.textContent = this.label("guide_title")
  }

  setAdvisorChrome() {
    if (this.hasEyebrowTarget) this.eyebrowTarget.textContent = this.label("eyebrow")
    if (this.hasTitleTarget) this.titleTarget.textContent = this.label("title")
  }

  hideGuidePanel() {
    if (this.hasGuidePanelTarget) this.guidePanelTarget.hidden = true
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
    const labels = this.labelsValue || {}
    if (labels[key]) return labels[key]
    if (key === "measure_hem" && labels.measure_waist) return labels.measure_waist
    return key
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

function formatMeasure(value) {
  const number = Number(value)
  if (!Number.isFinite(number)) return value
  return Number.isInteger(number) ? String(number) : String(round1(number))
}

function escapeHtml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
}
