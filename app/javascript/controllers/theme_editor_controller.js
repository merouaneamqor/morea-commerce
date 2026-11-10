import { Controller } from "@hotwired/stimulus"

const COPY_FIELDS = {
  hero: ["subheading", "heading", "button_label"],
  ticker: ["body"],
  featured_collection: ["subheading", "heading"],
  collection_list: ["subheading", "heading"],
  image_with_text: ["subheading", "heading", "body", "button_label"],
  rich_text: ["subheading", "body", "button_label"]
}

const SETTING_FIELDS = {
  hero: ["image_url", "link"],
  ticker: [],
  featured_collection: ["collection_id", "limit"],
  collection_list: ["limit"],
  image_with_text: ["image_url", "link", "image_position"],
  rich_text: ["image_url", "link"]
}

const FALLBACK_KINDS = [
  { kind: "hero", label: "Image banner", description: "Full-width banner with image and a call to action." },
  { kind: "ticker", label: "Scrolling text", description: "Scrolling lines of short announcement text." },
  { kind: "featured_collection", label: "Featured collection", description: "Product grid from one collection." },
  { kind: "collection_list", label: "Collection list", description: "Grid of published collections." },
  { kind: "image_with_text", label: "Image with text", description: "Image beside heading, body, and optional button." },
  { kind: "rich_text", label: "Rich text", description: "Centered text block with optional image and link." }
]

export default class extends Controller {
  static targets = [
    "payload", "sectionList", "preview", "previewFrame", "settingsForm", "settingsTitle", "locale",
    "saveStatus", "saveButton", "undoButton", "redoButton", "desktopButton", "mobileButton",
    "sectionPicker", "sectionPickerList", "emptyState", "addButton", "sectionCount"
  ]
  static values = {
    saveUrl: String,
    previewUrl: String,
    readOnly: Boolean,
    maxSections: { type: Number, default: 50 },
    sectionKinds: { type: Array, default: [] },
    removeConfirm: { type: String, default: "Remove this section from the theme draft?" },
    emptyEditor: { type: String, default: "No sections yet. Add one to start building this home page draft." }
  }

  connect() {
    this.snapshot = JSON.parse(this.payloadTarget.textContent)
    this.snapshot.sections ||= []
    this.locale = this.localeTarget.value
    this.selectedIndex = this.snapshot.sections.length ? 0 : -1
    this.undoStack = []
    this.redoStack = []
    this.dragIndex = null
    this.previewTimer = null
    this.previewRequestId = 0
    this.render()
    this.keyHandler = this.handleKeydown.bind(this)
    window.addEventListener("keydown", this.keyHandler)
  }

  disconnect() {
    window.removeEventListener("keydown", this.keyHandler)
    if (this.previewTimer) window.clearTimeout(this.previewTimer)
  }

  cloneSnapshot() { return JSON.parse(JSON.stringify(this.snapshot)) }

  kinds() {
    return this.sectionKindsValue.length ? this.sectionKindsValue : FALLBACK_KINDS
  }

  render({ refreshPreview = true } = {}) {
    this.renderTree()
    this.renderSettings()
    this.renderPicker()
    this.updateChrome()
    this.updateHistoryButtons()
    if (refreshPreview) this.queuePreviewRefresh()
  }

  renderTree() {
    this.sectionListTarget.replaceChildren()
    this.snapshot.sections.forEach((section, index) => {
      const item = document.createElement("li")
      item.className = `flex items-center gap-2 p-2 ${index === this.selectedIndex ? "bg-blue-50" : "bg-white"}`
      item.draggable = !this.readOnlyValue
      item.dataset.index = index
      item.addEventListener("dragstart", () => { this.dragIndex = index })
      item.addEventListener("dragover", event => event.preventDefault())
      item.addEventListener("drop", event => this.dropSection(event, index))
      const handle = document.createElement("span")
      handle.className = "cursor-grab select-none text-stone-400"
      handle.textContent = "⋮⋮"
      handle.setAttribute("aria-hidden", "true")
      const button = document.createElement("button")
      button.type = "button"
      button.className = "min-w-0 flex-1 rounded px-2 py-2 text-left text-sm font-medium focus:outline-none focus:ring-2 focus:ring-blue-500"
      button.textContent = this.labelFor(section.kind)
      button.addEventListener("click", () => { this.selectedIndex = index; this.render() })
      const state = document.createElement("span")
      state.className = "text-xs text-stone-500"
      state.textContent = section.visible === false ? "Hidden" : ""
      item.append(handle, button, state)
      this.sectionListTarget.append(item)
    })
  }

  queuePreviewRefresh(immediate = false) {
    if (!this.hasPreviewUrlValue || !this.previewUrlValue) return
    if (this.previewTimer) window.clearTimeout(this.previewTimer)
    if (immediate) {
      this.refreshPreview()
      return
    }
    this.previewTimer = window.setTimeout(() => this.refreshPreview(), 250)
  }

  async refreshPreview() {
    if (!this.hasPreviewUrlValue || !this.previewUrlValue) return
    const requestId = ++this.previewRequestId
    try {
      const response = await fetch(this.previewUrlValue, {
        method: "POST",
        headers: {
          "Accept": "text/html",
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || ""
        },
        body: JSON.stringify({ locale: this.locale, snapshot: this.snapshot })
      })
      if (!response.ok) throw new Error("Preview failed")
      const html = await response.text()
      if (requestId !== this.previewRequestId) return
      this.previewTarget.innerHTML = html
      this.bindPreviewSelection()
    } catch (_error) {
      if (requestId !== this.previewRequestId) return
      this.previewTarget.replaceChildren(this.textElement("p", "Storefront preview could not be loaded.", "px-6 py-16 text-center text-stone-500"))
    }
  }

  bindPreviewSelection() {
    this.previewTarget.querySelectorAll("[data-preview-index]").forEach(block => {
      block.addEventListener("click", () => {
        const index = Number(block.dataset.previewIndex)
        if (Number.isNaN(index)) return
        const visibleSections = this.snapshot.sections.filter(section => section.visible !== false)
        const section = visibleSections[index]
        if (!section) return
        this.selectedIndex = this.snapshot.sections.indexOf(section)
        this.render({ refreshPreview: false })
      })
    })
  }

  textElement(tag, value, classes) {
    const element = document.createElement(tag)
    element.className = classes
    element.textContent = value
    return element
  }

  renderSettings() {
    this.settingsFormTarget.replaceChildren()
    const section = this.snapshot.sections[this.selectedIndex]
    if (!section) {
      this.settingsTitleTarget.textContent = "Section settings"
      this.settingsFormTarget.append(this.textElement("p", "Select or add a section to edit its settings.", "text-sm text-stone-500"))
      return
    }
    this.settingsTitleTarget.textContent = this.labelFor(section.kind)
    this.settingsFormTarget.append(this.checkboxField("Visible", "visible", section.visible !== false))
    section.translations ||= {}
    section.translations[this.locale] ||= {}
    ;(COPY_FIELDS[section.kind] || []).forEach(field => this.settingsFormTarget.append(this.textField(this.humanize(field), `translations.${this.locale}.${field}`, section.translations[this.locale][field] || "", field === "body")))
    section.settings ||= {}
    ;(SETTING_FIELDS[section.kind] || []).forEach(field => this.settingsFormTarget.append(this.textField(this.humanize(field), `settings.${field}`, section.settings[field] || "")))

    if (!this.readOnlyValue) {
      const remove = document.createElement("button")
      remove.type = "button"
      remove.className = "admin-btn-critical mt-2"
      remove.textContent = "Remove section"
      remove.dataset.action = "theme-editor#removeSection"
      remove.addEventListener("click", () => this.removeSection())
      this.settingsFormTarget.append(remove)
    }

    Array.from(this.settingsFormTarget.elements).forEach(element => { element.disabled = this.readOnlyValue })
  }

  renderPicker() {
    if (!this.hasSectionPickerListTarget) return
    this.sectionPickerListTarget.replaceChildren()
    const atLimit = this.snapshot.sections.length >= this.maxSectionsValue
    this.kinds().forEach(entry => {
      const item = document.createElement("li")
      const button = document.createElement("button")
      button.type = "button"
      button.className = "flex w-full flex-col gap-1 rounded-md border border-[#dedede] bg-white px-3 py-3 text-left hover:bg-stone-50 focus:outline-none focus:ring-2 focus:ring-blue-500 disabled:cursor-not-allowed disabled:opacity-50"
      button.disabled = this.readOnlyValue || atLimit
      button.dataset.kind = entry.kind
      button.addEventListener("click", () => this.addSection(entry.kind))
      const title = document.createElement("span")
      title.className = "text-sm font-semibold"
      title.textContent = entry.label || this.labelFor(entry.kind)
      const description = document.createElement("span")
      description.className = "text-sm text-stone-500"
      description.textContent = entry.description || ""
      button.append(title, description)
      item.append(button)
      this.sectionPickerListTarget.append(item)
    })
  }

  updateChrome() {
    const count = this.snapshot.sections.length
    if (this.hasSectionCountTarget) {
      this.sectionCountTarget.textContent = count === 1 ? "1 section" : `${count} sections`
    }
    if (this.hasEmptyStateTarget) {
      this.emptyStateTarget.hidden = count > 0
      this.emptyStateTarget.textContent = this.emptyEditorValue
    }
    if (this.hasAddButtonTarget) {
      this.addButtonTarget.disabled = this.readOnlyValue || count >= this.maxSectionsValue
      this.addButtonTarget.title = count >= this.maxSectionsValue ? `A theme can have at most ${this.maxSectionsValue} sections.` : "Add a section"
    }
  }

  textField(labelText, path, value, multiline = false) {
    const wrapper = document.createElement("label"); wrapper.className = "block"
    const label = document.createElement("span"); label.className = "mb-1 block text-sm font-medium"; label.textContent = labelText
    const input = document.createElement(multiline ? "textarea" : "input")
    if (!multiline) input.type = "text"
    input.className = "admin-input w-full"
    if (multiline) input.rows = 4
    input.value = value
    input.dataset.path = path
    wrapper.append(label, input)
    return wrapper
  }

  checkboxField(labelText, path, checked) {
    const label = document.createElement("label"); label.className = "flex items-center gap-2 text-sm font-medium"
    const input = document.createElement("input"); input.type = "checkbox"; input.checked = checked; input.dataset.path = path
    const text = document.createElement("span"); text.textContent = labelText
    label.append(input, text)
    return label
  }

  updateField(event) {
    if (this.readOnlyValue || !event.target.dataset.path) return
    this.remember()
    const section = this.snapshot.sections[this.selectedIndex]
    const parts = event.target.dataset.path.split(".")
    let target = section
    parts.slice(0, -1).forEach(key => { target[key] ||= {}; target = target[key] })
    target[parts.at(-1)] = event.target.type === "checkbox" ? event.target.checked : event.target.value
    this.markUnsaved()
    this.renderTree()
    this.updateHistoryButtons()
    this.queuePreviewRefresh()
  }

  dropSection(event, targetIndex) {
    event.preventDefault()
    if (this.readOnlyValue || this.dragIndex === null || this.dragIndex === targetIndex) return
    this.remember()
    const [moved] = this.snapshot.sections.splice(this.dragIndex, 1)
    this.snapshot.sections.splice(targetIndex, 0, moved)
    this.selectedIndex = targetIndex
    this.dragIndex = null
    this.markUnsaved(); this.render()
  }

  openPicker() {
    if (this.readOnlyValue || !this.hasSectionPickerTarget) return
    if (this.snapshot.sections.length >= this.maxSectionsValue) {
      this.saveStatusTarget.textContent = `· A theme can have at most ${this.maxSectionsValue} sections.`
      return
    }
    this.renderPicker()
    if (typeof this.sectionPickerTarget.showModal === "function") {
      this.sectionPickerTarget.showModal()
    } else {
      this.sectionPickerTarget.setAttribute("open", "")
    }
  }

  closePicker() {
    if (!this.hasSectionPickerTarget) return
    if (typeof this.sectionPickerTarget.close === "function") {
      this.sectionPickerTarget.close()
    } else {
      this.sectionPickerTarget.removeAttribute("open")
    }
  }

  addSection(kindOrEvent) {
    if (this.readOnlyValue) return
    const kind = typeof kindOrEvent === "string" ? kindOrEvent : kindOrEvent?.currentTarget?.dataset?.kind
    if (!kind || !this.kinds().some(entry => entry.kind === kind)) return
    if (this.snapshot.sections.length >= this.maxSectionsValue) {
      this.saveStatusTarget.textContent = `· A theme can have at most ${this.maxSectionsValue} sections.`
      this.closePicker()
      return
    }

    this.remember()
    const insertAt = this.selectedIndex >= 0 ? this.selectedIndex + 1 : this.snapshot.sections.length
    this.snapshot.sections.splice(insertAt, 0, this.blankSection(kind))
    this.selectedIndex = insertAt
    this.markUnsaved()
    this.closePicker()
    this.render()
  }

  blankSection(kind) {
    return {
      kind,
      visible: true,
      settings: {},
      translations: { fr: {}, en: {}, ar: {} }
    }
  }

  removeSection() {
    if (this.readOnlyValue || this.selectedIndex < 0) return
    const section = this.snapshot.sections[this.selectedIndex]
    if (!section) return
    if (!window.confirm(this.removeConfirmValue)) return

    this.remember()
    this.snapshot.sections.splice(this.selectedIndex, 1)
    if (!this.snapshot.sections.length) {
      this.selectedIndex = -1
    } else {
      this.selectedIndex = Math.min(this.selectedIndex, this.snapshot.sections.length - 1)
    }
    this.markUnsaved()
    this.render()
  }

  remember() { this.undoStack.push(this.cloneSnapshot()); if (this.undoStack.length > 50) this.undoStack.shift(); this.redoStack = [] }
  undo() {
    if (!this.undoStack.length || this.readOnlyValue) return
    this.redoStack.push(this.cloneSnapshot())
    this.snapshot = this.undoStack.pop()
    this.selectedIndex = this.snapshot.sections.length ? Math.min(Math.max(this.selectedIndex, 0), this.snapshot.sections.length - 1) : -1
    this.markUnsaved(); this.render()
  }
  redo() {
    if (!this.redoStack.length || this.readOnlyValue) return
    this.undoStack.push(this.cloneSnapshot())
    this.snapshot = this.redoStack.pop()
    this.selectedIndex = this.snapshot.sections.length ? Math.min(Math.max(this.selectedIndex, 0), this.snapshot.sections.length - 1) : -1
    this.markUnsaved(); this.render()
  }
  changeLocale() {
    this.locale = this.localeTarget.value
    this.renderSettings()
    this.queuePreviewRefresh(true)
  }
  setDesktop() { this.previewFrameTarget.style.maxWidth = "none"; this.setDeviceButtons(true) }
  setMobile() { this.previewFrameTarget.style.maxWidth = "390px"; this.setDeviceButtons(false) }
  setDeviceButtons(desktop) { this.desktopButtonTarget.setAttribute("aria-pressed", desktop); this.mobileButtonTarget.setAttribute("aria-pressed", !desktop); this.desktopButtonTarget.classList.toggle("bg-stone-200", desktop); this.mobileButtonTarget.classList.toggle("bg-stone-200", !desktop) }

  async save() {
    if (this.readOnlyValue) return
    this.saveButtonTarget.disabled = true
    this.saveStatusTarget.textContent = "· Saving…"
    try {
      const response = await fetch(this.saveUrlValue, { method: "PATCH", headers: { "Accept": "application/json", "Content-Type": "application/json", "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || "" }, body: JSON.stringify({ snapshot: this.snapshot }) })
      const result = await response.json()
      if (!response.ok || !result.saved) throw new Error(result.error || "Save failed")
      this.saveStatusTarget.textContent = "· Saved"
    } catch (error) { this.saveStatusTarget.textContent = `· ${error.message}` }
    finally { this.saveButtonTarget.disabled = false }
  }

  handleKeydown(event) {
    if (!(event.ctrlKey || event.metaKey)) return
    const key = event.key.toLowerCase()
    if (key === "s") { event.preventDefault(); this.save() }
    if (key === "z" && !event.shiftKey) { event.preventDefault(); this.undo() }
    if (key === "y" || (key === "z" && event.shiftKey)) { event.preventDefault(); this.redo() }
  }

  markUnsaved() { this.saveStatusTarget.textContent = "· Unsaved changes" }
  updateHistoryButtons() { this.undoButtonTarget.disabled = this.readOnlyValue || !this.undoStack.length; this.redoButtonTarget.disabled = this.readOnlyValue || !this.redoStack.length }
  labelFor(kind) {
    const entry = this.kinds().find(item => item.kind === kind)
    return entry?.label || ({ hero: "Image banner", ticker: "Scrolling text", featured_collection: "Featured collection", collection_list: "Collection list", image_with_text: "Image with text", rich_text: "Rich text" })[kind] || this.humanize(kind)
  }
  humanize(value) { return String(value || "").replaceAll("_", " ").replace(/^./, character => character.toUpperCase()) }
}
