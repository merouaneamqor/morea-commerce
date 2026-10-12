import { Controller } from "@hotwired/stimulus"

// Size checklist + color picker list that generates a size × color variant table.
// sizeOrder / placeholderHex are injected from ProductVariant constants via the ERB partial.
export default class extends Controller {
  static targets = [
    "sizeList", "sizeOption", "customSize",
    "colorList", "colorTemplate",
    "tbody", "rowTemplate", "empty", "destroyIds", "groupBy"
  ]

  static values = {
    sizeOrder: { type: Array, default: ["XS", "S", "M", "L", "XL", "XXL"] },
    placeholderHex: { type: String, default: "#c4b8b0" }
  }

  connect() {
    this.regroup()
    this.refreshEmpty()
  }

  // —— Sizes ——

  selectedSizes() {
    const fromChecks = this.sizeOptionTargets
      .filter((input) => input.checked)
      .map((input) => input.value.trim())
      .filter(Boolean)

    const fromChips = Array.from(this.sizeListTarget.querySelectorAll("[data-variant-matrix-size-chip]"))
      .map((chip) => chip.dataset.size?.trim())
      .filter(Boolean)

    return [...new Set([...fromChecks, ...fromChips])]
  }

  syncSizes() {
    // checkboxes drive generate(); no extra work needed
  }

  addCustomSize(event) {
    event.preventDefault()
    if (!this.hasCustomSizeTarget) return

    const size = this.customSizeTarget.value.trim()
    if (!size) return

    const existing = this.selectedSizes().map((s) => s.toUpperCase())
    if (existing.includes(size.toUpperCase())) {
      this.customSizeTarget.value = ""
      return
    }

    const preset = this.sizeOptionTargets.find((input) => input.value.toUpperCase() === size.toUpperCase())
    if (preset) {
      preset.checked = true
      this.customSizeTarget.value = ""
      return
    }

    const chip = document.createElement("span")
    chip.className = "inline-flex items-center gap-2 rounded-lg border border-[#ebebeb] px-3 py-2 text-[13px]"
    chip.dataset.variantMatrixSizeChip = ""
    chip.dataset.size = size
    chip.innerHTML = `
      ${this.escapeHtml(size)}
      <button type="button" class="admin-btn-plain admin-btn-plain--critical text-xs"
              data-action="variant-matrix#removeSizeChip" aria-label="Remove ${this.escapeAttr(size)}">×</button>
    `
    this.sizeListTarget.appendChild(chip)
    this.customSizeTarget.value = ""
  }

  removeSizeChip(event) {
    event.preventDefault()
    event.currentTarget.closest("[data-variant-matrix-size-chip]")?.remove()
  }

  // —— Colors ——

  selectedColors() {
    return Array.from(this.colorListTarget.querySelectorAll("[data-variant-matrix-color-row]")).flatMap((row) => {
      const name = row.querySelector('[data-field="name"]')?.value?.trim()
      if (!name) return []
      const hex = this.normalizeHex(row.querySelector('[data-field="hex"]')?.value)
      return [{ name, hex: hex || "" }]
    })
  }

  addColor(event) {
    event.preventDefault()
    if (!this.hasColorTemplateTarget) return
    this.colorListTarget.insertAdjacentHTML("beforeend", this.colorTemplateTarget.innerHTML)
    const row = this.colorListTarget.querySelector("[data-variant-matrix-color-row]:last-child")
    row?.querySelector('[data-field="name"]')?.focus()
  }

  removeColor(event) {
    event.preventDefault()
    event.currentTarget.closest("[data-variant-matrix-color-row]")?.remove()
  }

  syncColorPicker(event) {
    const row = event.currentTarget.closest("[data-variant-matrix-color-row]")
    if (!row) return
    const hex = this.normalizeHex(event.currentTarget.value)
    const hexInput = row.querySelector('[data-field="hex"]')
    if (hexInput) hexInput.value = hex
    this.applyColorHex(row.querySelector('[data-field="name"]')?.value, hex)
  }

  syncColorHex(event) {
    const row = event.currentTarget.closest("[data-variant-matrix-color-row]")
    if (!row) return
    const hex = this.normalizeHex(event.currentTarget.value)
    if (!hex) return
    event.currentTarget.value = hex
    const picker = row.querySelector('[data-field="hex-picker"]')
    if (picker) picker.value = hex
    this.applyColorHex(row.querySelector('[data-field="name"]')?.value, hex)
  }

  syncColorNames(event) {
    const row = event.currentTarget.closest("[data-variant-matrix-color-row]")
    if (!row) return
    const name = event.currentTarget.value.trim()
    const hex = this.normalizeHex(row.querySelector('[data-field="hex"]')?.value)
    this.applyColorHex(name, hex)
  }

  applyColorHex(name, hex) {
    if (!name) return
    const resolved = this.normalizeHex(hex) || ""
    this.rows().forEach((row) => {
      if (this.rowColor(row) !== name.trim()) return
      row.dataset.colorHex = resolved
      const hexField = row.querySelector('[data-field="color_hex"]')
      if (hexField) hexField.value = resolved
      const swatch = row.querySelector('[data-field="swatch"]')
      if (swatch) swatch.style.background = resolved || this.placeholderHexValue
    })
  }

  // —— Generate / table ——

  generate(event) {
    event.preventDefault()
    const sizes = this.selectedSizes()
    const colors = this.selectedColors()
    const combos = this.combinations(sizes, colors)

    colors.forEach(({ name, hex }) => this.applyColorHex(name, hex))

    if (!combos.length) {
      return
    }

    const existing = new Set(this.rows().map((row) => this.rowKey(row)))
    combos.forEach(([size, color, hex]) => {
      const key = `${size}\0${color}`
      if (existing.has(key)) return
      this.addRow(size, color, hex)
      existing.add(key)
    })

    this.regroup()
    this.refreshEmpty()
  }

  remove(event) {
    event.preventDefault()
    const row = event.currentTarget.closest("[data-variant-matrix-row]")
    if (!row) return

    const id = row.dataset.variantId
    if (id) {
      this.appendDestroyId(id)
    }
    row.remove()
    this.regroup()
    this.refreshEmpty()
  }

  regroup() {
    const mode = this.hasGroupByTarget ? this.groupByTarget.value : "none"
    const rows = this.rows()
    this.clearGroupHeaders()

    if (!rows.length) {
      return
    }

    const sorted = this.sortRows(rows, mode)
    sorted.forEach((row) => this.tbodyTarget.appendChild(row))

    if (mode === "none") {
      return
    }

    let currentKey = null
    sorted.forEach((row) => {
      const key = mode === "size" ? this.rowSize(row) : this.rowColor(row)
      if (key !== currentKey) {
        currentKey = key
        const header = this.buildGroupHeader(mode, key, row, sorted.filter((r) => {
          return (mode === "size" ? this.rowSize(r) : this.rowColor(r)) === key
        }).length)
        this.tbodyTarget.insertBefore(header, row)
      }
    })
  }

  combinations(sizes, colors) {
    if (sizes.length && colors.length) {
      return sizes.flatMap((size) => colors.map(({ name, hex }) => [size, name, hex]))
    }
    if (sizes.length) {
      return sizes.map((size) => [size, "", ""])
    }
    if (colors.length) {
      return colors.map(({ name, hex }) => ["", name, hex])
    }
    return []
  }

  rows() {
    return Array.from(this.tbodyTarget.querySelectorAll("[data-variant-matrix-row]"))
  }

  clearGroupHeaders() {
    this.tbodyTarget.querySelectorAll("[data-variant-matrix-group]").forEach((el) => el.remove())
  }

  rowKey(row) {
    return `${this.rowSize(row)}\0${this.rowColor(row)}`
  }

  rowSize(row) {
    return (row.dataset.size || row.querySelector('[data-field="option1_value"]')?.value || "").trim()
  }

  rowColor(row) {
    return (row.dataset.color || row.querySelector('[data-field="option2_value"]')?.value || "").trim()
  }

  sortRows(rows, mode) {
    return [...rows].sort((a, b) => {
      const sizeA = this.rowSize(a)
      const sizeB = this.rowSize(b)
      const colorA = this.rowColor(a)
      const colorB = this.rowColor(b)

      if (mode === "color") {
        return this.compareText(colorA, colorB) || this.compareSize(sizeA, sizeB)
      }

      return this.compareSize(sizeA, sizeB) || this.compareText(colorA, colorB)
    })
  }

  compareSize(a, b) {
    const order = this.sizeOrderValue
    const ia = order.indexOf(a.toUpperCase())
    const ib = order.indexOf(b.toUpperCase())
    const na = ia === -1 ? 99 : ia
    const nb = ib === -1 ? 99 : ib
    return na - nb || this.compareText(a, b)
  }

  compareText(a, b) {
    return a.localeCompare(b, undefined, { sensitivity: "base" })
  }

  buildGroupHeader(mode, key, sampleRow, count) {
    const label = key || "—"
    const title = mode === "size" ? `Size: ${label}` : `Color: ${label}`
    const hex = mode === "color" ? this.normalizeHex(sampleRow.dataset.colorHex) : null
    const swatch = mode === "color"
      ? `<span class="inline-block h-3 w-3 rounded-full border border-[#d4d4d4]" style="background: ${this.escapeAttr(hex || this.placeholderHexValue)}"></span>`
      : ""
    const tr = document.createElement("tr")
    tr.dataset.variantMatrixGroup = mode
    tr.innerHTML = `
      <td colspan="6" class="!bg-[#f7f7f7]">
        <div class="flex flex-wrap items-center justify-between gap-2 py-0.5">
          <span class="inline-flex items-center gap-2 text-xs font-medium uppercase tracking-wide text-[#616161]">
            ${swatch}${this.escapeHtml(title)}
          </span>
          <span class="admin-muted">${count} ${count === 1 ? "variant" : "variants"}</span>
        </div>
      </td>
    `
    return tr
  }

  addRow(size, color, hex) {
    const resolvedHex = color ? (this.normalizeHex(hex) || "") : ""
    const html = this.rowTemplateTarget.innerHTML
      .replaceAll("__INDEX__", String(Date.now() + Math.floor(Math.random() * 1000)))
      .replaceAll("__SIZE__", this.escapeAttr(size))
      .replaceAll("__COLOR__", this.escapeAttr(color))
      .replaceAll("__HEX__", this.escapeAttr(resolvedHex))
      .replaceAll("__NAME__", this.escapeHtml(this.displayName(size, color)))
      .replaceAll("__SWATCH_HIDDEN__", color ? "" : "hidden")

    this.tbodyTarget.insertAdjacentHTML("beforeend", html)
    const row = this.tbodyTarget.querySelector("[data-variant-matrix-row]:last-child")
    const swatch = row?.querySelector('[data-field="swatch"]')
    if (swatch) swatch.style.background = resolvedHex || this.placeholderHexValue
  }

  displayName(size, color) {
    return [size, color].filter(Boolean).join(" / ")
  }

  appendDestroyId(id) {
    if (!this.hasDestroyIdsTarget) return
    const value = String(id)
    const already = Array.from(this.destroyIdsTarget.querySelectorAll('input[name="destroy_ids[]"]'))
      .some((input) => input.value === value)
    if (already) return

    const input = document.createElement("input")
    input.type = "hidden"
    input.name = "destroy_ids[]"
    input.value = value
    this.destroyIdsTarget.appendChild(input)
  }

  refreshEmpty() {
    if (!this.hasEmptyTarget) return
    this.emptyTarget.hidden = this.rows().length > 0
  }

  // Mirrors ProductVariant.normalize_hex (client-side for picker UX).
  normalizeHex(value) {
    let hex = String(value || "").trim()
    if (!hex) return ""
    if (/^[0-9a-fA-F]{6}$/.test(hex)) hex = `#${hex}`
    if (!/^#[0-9a-fA-F]{6}$/.test(hex)) return ""
    return hex.toLowerCase()
  }

  escapeAttr(value) {
    return String(value)
      .replaceAll("&", "&amp;")
      .replaceAll('"', "&quot;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
  }

  escapeHtml(value) {
    return String(value)
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
  }
}
