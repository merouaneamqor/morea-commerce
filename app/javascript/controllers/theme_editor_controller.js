import { Controller } from "@hotwired/stimulus"

const COPY_FIELDS = {
  hero: ["subheading", "heading", "body", "button_label"],
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
  { kind: "hero", label: "Image banner", description: "Full-bleed banner with brand, headline, supporting line, and a primary call to action." },
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
    imageUrl: String,
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
    if (refreshPreview) {
      this.queuePreviewRefresh()
    } else {
      this.highlightPreviewSelection()
    }
  }

  renderTree() {
    this.sectionListTarget.replaceChildren()
    this.snapshot.sections.forEach((section, index) => {
      const hidden = section.visible === false
      const item = document.createElement("li")
      item.className = `te-section${index === this.selectedIndex ? " is-selected" : ""}${hidden ? " is-hidden" : ""}`
      item.draggable = !this.readOnlyValue
      item.dataset.index = index
      item.addEventListener("dragstart", () => { this.dragIndex = index })
      item.addEventListener("dragover", event => event.preventDefault())
      item.addEventListener("drop", event => this.dropSection(event, index))

      const handle = document.createElement("span")
      handle.className = "te-grip"
      handle.setAttribute("aria-hidden", "true")
      handle.innerHTML = `<svg width="14" height="14" viewBox="0 0 14 14"><circle cx="5" cy="3" r="1"/><circle cx="9" cy="3" r="1"/><circle cx="5" cy="7" r="1"/><circle cx="9" cy="7" r="1"/><circle cx="5" cy="11" r="1"/><circle cx="9" cy="11" r="1"/></svg>`

      const button = document.createElement("button")
      button.type = "button"
      button.className = "te-section__name"
      button.textContent = this.labelFor(section.kind)
      button.addEventListener("click", () => this.selectSection(index))

      const eye = document.createElement("button")
      eye.type = "button"
      eye.className = "te-section__eye"
      eye.disabled = this.readOnlyValue
      eye.setAttribute("aria-pressed", hidden ? "false" : "true")
      eye.setAttribute("aria-label", hidden ? `Show ${button.textContent}` : `Hide ${button.textContent}`)
      eye.innerHTML = hidden
        ? `<svg width="16" height="16" viewBox="0 0 16 16" aria-hidden="true"><path d="M2 2.8 14 13.2" fill="none" stroke="currentColor" stroke-width="1.3" stroke-linecap="round"/><path d="M6.2 6.4A2.2 2.2 0 0 0 9.7 9.8M3.2 5.6C2.2 6.5 1.5 7.6 1.5 8s2.4 4.2 6.5 4.2c1.1 0 2.1-.2 3-.6M6.4 3.9c.5-.1 1-.2 1.6-.2 4.1 0 6.5 4.3 6.5 4.3s-.6 1-1.7 2" fill="none" stroke="currentColor" stroke-width="1.3" stroke-linecap="round" stroke-linejoin="round"/></svg>`
        : `<svg width="16" height="16" viewBox="0 0 16 16" aria-hidden="true"><path d="M1.5 8S3.9 3.8 8 3.8 14.5 8 14.5 8 12.1 12.2 8 12.2 1.5 8 1.5 8Z" fill="none" stroke="currentColor" stroke-width="1.3"/><circle cx="8" cy="8" r="2" fill="none" stroke="currentColor" stroke-width="1.3"/></svg>`
      eye.addEventListener("click", event => {
        event.stopPropagation()
        this.toggleVisible(index)
      })

      item.append(handle, button, eye)
      this.sectionListTarget.append(item)
    })
  }

  selectSection(index) {
    this.selectedIndex = index
    this.render()
    if (window.matchMedia("(max-width: 1080px)").matches) this.setPane("settings")
  }

  showPane(event) {
    this.setPane(event.currentTarget.dataset.themeEditorPane)
  }

  setPane(name) {
    if (!name) return
    this.element.dataset.editorPane = name
    this.element.querySelectorAll("[data-theme-editor-pane]").forEach(button => {
      button.setAttribute("aria-pressed", button.dataset.themeEditorPane === name ? "true" : "false")
    })
  }

  toggleVisible(index) {
    if (this.readOnlyValue || !this.snapshot.sections[index]) return
    this.selectedIndex = index
    this.remember()
    const section = this.snapshot.sections[index]
    section.visible = section.visible === false
    this.markUnsaved()
    this.render()
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
        body: JSON.stringify({ locale: this.locale, snapshot: this.snapshot, selected_index: this.selectedIndex })
      })
      if (!response.ok) throw new Error("Preview failed")
      const html = await response.text()
      if (requestId !== this.previewRequestId) return
      this.previewTarget.innerHTML = html
      this.bindPreviewSelection()
      this.highlightPreviewSelection()
    } catch (_error) {
      if (requestId !== this.previewRequestId) return
      this.previewTarget.replaceChildren(this.textElement("p", "Storefront preview could not be loaded.", "te-empty"))
    }
  }

  bindPreviewSelection() {
    this.previewTarget.querySelectorAll("[data-section-index]").forEach(block => {
      block.addEventListener("click", event => {
        event.preventDefault()
        this.selectPreviewSection(block)
      })
      block.addEventListener("keydown", event => {
        if (event.key === "Enter" || event.key === " ") {
          event.preventDefault()
          this.selectPreviewSection(block)
          return
        }
        if (event.key === "ArrowDown" || event.key === "ArrowUp") {
          event.preventDefault()
          this.focusAdjacentPreviewSection(block, event.key === "ArrowDown" ? 1 : -1)
        }
      })
    })
  }

  selectPreviewSection(block) {
    const index = Number(block.dataset.sectionIndex)
    if (Number.isNaN(index) || !this.snapshot.sections[index]) return
    this.selectedIndex = index
    this.render({ refreshPreview: false })
    this.highlightPreviewSelection({ focus: true })
    if (window.matchMedia("(max-width: 1080px)").matches) this.setPane("settings")
  }

  focusAdjacentPreviewSection(block, delta) {
    const blocks = Array.from(this.previewTarget.querySelectorAll("[data-section-index]"))
    const current = blocks.indexOf(block)
    if (current < 0) return
    const next = blocks[current + delta]
    if (next) next.focus()
  }

  highlightPreviewSelection({ focus = false } = {}) {
    this.previewTarget.querySelectorAll("[data-section-index]").forEach(block => {
      const selected = Number(block.dataset.sectionIndex) === this.selectedIndex
      block.classList.toggle("is-selected", selected)
      block.setAttribute("aria-pressed", selected ? "true" : "false")
      if (selected && focus) block.focus({ preventScroll: false })
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
      this.settingsFormTarget.append(this.textElement("p", "Select a section to edit it.", "te-hint"))
      return
    }
    this.settingsTitleTarget.textContent = this.labelFor(section.kind)
    section.translations ||= {}
    section.translations[this.locale] ||= {}
    const copyFields = COPY_FIELDS[section.kind] || []
    if (copyFields.length) this.settingsFormTarget.append(this.groupLabel("Content"))
    copyFields.forEach(field => this.settingsFormTarget.append(this.textField(this.humanize(field), `translations.${this.locale}.${field}`, section.translations[this.locale][field] || "", field === "body")))
    section.settings ||= {}
    const settingFields = SETTING_FIELDS[section.kind] || []
    if (settingFields.length) this.settingsFormTarget.append(this.groupLabel("Settings"))
    settingFields.forEach(field => this.settingsFormTarget.append(this.settingField(field, section.settings[field] || "")))

    if (!this.readOnlyValue) {
      const remove = document.createElement("button")
      remove.type = "button"
      remove.className = "te-remove"
      remove.textContent = "Remove section"
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
      button.disabled = this.readOnlyValue || atLimit
      button.dataset.kind = entry.kind
      button.addEventListener("click", () => this.addSection(entry.kind))
      const title = document.createElement("strong")
      title.textContent = entry.label || this.labelFor(entry.kind)
      const description = document.createElement("span")
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

  settingField(field, value) {
    if (field === "image_url") return this.imageField(value)
    if (field === "image_position") return this.selectField("Image position", "settings.image_position", value || "left", [["left", "Left"], ["right", "Right"]])
    if (field === "limit") return this.selectField("Products to show", "settings.limit", String(value || "4"), ["2", "3", "4", "6", "8", "12"].map(count => [count, count]))
    if (field === "collection_id") return this.textField("Collection", "settings.collection_id", value)
    if (field === "link") return this.textField("Button link", "settings.link", value)
    return this.textField(this.humanize(field), `settings.${field}`, value)
  }

  imageField(value) {
    const wrapper = document.createElement("div")
    wrapper.className = "te-image"
    const src = this.safeImage(value)
    const frame = document.createElement("div")
    frame.className = "te-image__frame"
    if (src) {
      const preview = document.createElement("img")
      preview.alt = ""
      preview.src = src
      frame.append(preview)
    } else {
      frame.append(this.textElement("p", "No image yet", "te-image__placeholder"))
    }

    const row = document.createElement("div")
    row.className = "te-image__row"
    const upload = document.createElement("button")
    upload.type = "button"
    upload.className = "te-btn"
    upload.textContent = src ? "Replace" : "Upload image"
    upload.disabled = this.readOnlyValue
    const input = document.createElement("input")
    input.type = "file"
    input.accept = "image/jpeg,image/png,image/gif,image/webp"
    input.hidden = true
    input.disabled = this.readOnlyValue
    const status = document.createElement("p")
    status.className = "te-error"
    upload.addEventListener("click", () => input.click())
    input.addEventListener("change", () => {
      const file = input.files?.[0]
      if (file) this.uploadImage(file, upload, status)
    })
    row.append(upload)
    if (src && !this.readOnlyValue) {
      const remove = document.createElement("button")
      remove.type = "button"
      remove.className = "te-btn-quiet"
      remove.textContent = "Remove"
      remove.addEventListener("click", () => this.setImage(""))
      row.append(remove)
    }
    wrapper.append(frame, row, this.textElement("p", "JPEG, PNG, GIF, or WebP. 8 MB max.", "te-hint"), status, input)
    return wrapper
  }

  async uploadImage(file, caption, status) {
    if (this.readOnlyValue || !this.imageUrlValue) return
    const previous = caption.textContent
    caption.textContent = "Uploading…"
    caption.disabled = true
    if (status) status.textContent = ""
    const body = new FormData()
    body.append("image", file)
    try {
      const response = await fetch(this.imageUrlValue, {
        method: "POST",
        headers: { Accept: "application/json", "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || "" },
        body
      })
      const result = await response.json().catch(() => null)
      if (!result) throw new Error("The image could not be uploaded. Refresh the page and try again.")
      if (!response.ok || !result.url) throw new Error(result.error || "Upload failed")
      this.setImage(result.url)
    } catch (error) {
      caption.textContent = previous
      caption.disabled = false
      if (status) status.textContent = error.message
    }
  }

  setImage(url) {
    if (this.readOnlyValue || this.selectedIndex < 0) return
    this.remember()
    const section = this.snapshot.sections[this.selectedIndex]
    section.settings ||= {}
    section.settings.image_url = url
    this.markUnsaved()
    this.render()
  }

  selectField(labelText, path, value, options) {
    const wrapper = document.createElement("label")
    wrapper.className = "te-field"
    const label = document.createElement("span")
    label.textContent = labelText
    const select = document.createElement("select")
    select.dataset.path = path
    options.forEach(([optionValue, optionLabel]) => {
      const option = document.createElement("option")
      option.value = optionValue
      option.textContent = optionLabel
      option.selected = optionValue === String(value)
      select.append(option)
    })
    wrapper.append(label, select)
    return wrapper
  }

  safeImage(url) {
    if (!url) return ""
    try {
      const parsed = new URL(url, window.location.origin)
      if (parsed.protocol === "http:" || parsed.protocol === "https:") return parsed.href
    } catch { /* ignore unreadable values */ }
    return ""
  }

  textField(labelText, path, value, multiline = false) {
    const wrapper = document.createElement("label")
    wrapper.className = "te-field"
    const label = document.createElement("span")
    label.textContent = labelText
    const input = document.createElement(multiline ? "textarea" : "input")
    if (!multiline) input.type = "text"
    if (multiline) input.rows = 4
    input.value = value
    input.dataset.path = path
    wrapper.append(label, input)
    return wrapper
  }

  groupLabel(text) {
    const label = document.createElement("p")
    label.className = "te-group"
    label.textContent = text
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
      this.saveStatusTarget.textContent = `A theme can have at most ${this.maxSectionsValue} sections.`
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
      this.saveStatusTarget.textContent = `A theme can have at most ${this.maxSectionsValue} sections.`
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
    if (window.matchMedia("(max-width: 1080px)").matches) this.setPane("settings")
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
  setDesktop() { this.previewFrameTarget.classList.remove("is-mobile"); this.setDeviceButtons(true) }
  setMobile() { this.previewFrameTarget.classList.add("is-mobile"); this.setDeviceButtons(false) }
  setDeviceButtons(desktop) {
    this.desktopButtonTarget.setAttribute("aria-pressed", String(desktop))
    this.mobileButtonTarget.setAttribute("aria-pressed", String(!desktop))
  }

  async save() {
    if (this.readOnlyValue) return
    this.saveButtonTarget.disabled = true
    this.saveStatusTarget.textContent = "Saving…"
    try {
      const response = await fetch(this.saveUrlValue, { method: "PATCH", headers: { "Accept": "application/json", "Content-Type": "application/json", "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || "" }, body: JSON.stringify({ snapshot: this.snapshot }) })
      const result = await response.json()
      if (!response.ok || !result.saved) throw new Error(result.error || "Save failed")
      this.saveStatusTarget.textContent = "Saved"
    } catch (error) { this.saveStatusTarget.textContent = error.message }
    finally { this.saveButtonTarget.disabled = false }
  }

  handleKeydown(event) {
    if (!(event.ctrlKey || event.metaKey)) return
    const key = event.key.toLowerCase()
    if (key === "s") { event.preventDefault(); this.save() }
    if (key === "z" && !event.shiftKey) { event.preventDefault(); this.undo() }
    if (key === "y" || (key === "z" && event.shiftKey)) { event.preventDefault(); this.redo() }
  }

  markUnsaved() { this.saveStatusTarget.textContent = "Unsaved changes" }
  updateHistoryButtons() { this.undoButtonTarget.disabled = this.readOnlyValue || !this.undoStack.length; this.redoButtonTarget.disabled = this.readOnlyValue || !this.redoStack.length }
  labelFor(kind) {
    const entry = this.kinds().find(item => item.kind === kind)
    return entry?.label || ({ hero: "Image banner", ticker: "Scrolling text", featured_collection: "Featured collection", collection_list: "Collection list", image_with_text: "Image with text", rich_text: "Rich text" })[kind] || this.humanize(kind)
  }
  humanize(value) { return String(value || "").replaceAll("_", " ").replace(/^./, character => character.toUpperCase()) }
}
