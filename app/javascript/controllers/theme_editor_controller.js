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

export default class extends Controller {
  static targets = ["payload", "sectionList", "preview", "previewFrame", "settingsForm", "settingsTitle", "locale", "saveStatus", "saveButton", "undoButton", "redoButton", "desktopButton", "mobileButton"]
  static values = { saveUrl: String, readOnly: Boolean }

  connect() {
    this.snapshot = JSON.parse(this.payloadTarget.textContent)
    this.snapshot.sections ||= []
    this.locale = this.localeTarget.value
    this.selectedIndex = 0
    this.undoStack = []
    this.redoStack = []
    this.dragIndex = null
    this.render()
    this.keyHandler = this.handleKeydown.bind(this)
    window.addEventListener("keydown", this.keyHandler)
  }

  disconnect() { window.removeEventListener("keydown", this.keyHandler) }

  cloneSnapshot() { return JSON.parse(JSON.stringify(this.snapshot)) }

  render() {
    this.renderTree()
    this.renderPreview()
    this.renderSettings()
    this.updateHistoryButtons()
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

  renderPreview() {
    this.previewTarget.replaceChildren()
    this.previewTarget.dir = this.locale === "ar" ? "rtl" : "ltr"
    this.snapshot.sections.filter(section => section.visible !== false).forEach((section, index) => {
      const copy = section.translations?.[this.locale] || {}
      const block = document.createElement("section")
      block.className = section.kind === "hero" ? "border-b bg-[#eee5dc] px-6 py-16 text-center" : "border-b px-6 py-9"
      block.tabIndex = 0
      block.addEventListener("click", () => { this.selectedIndex = this.snapshot.sections.indexOf(section); this.render() })
      if (copy.subheading) block.append(this.textElement("p", copy.subheading, "mb-2 text-xs uppercase tracking-[.2em] text-stone-500"))
      if (copy.heading) block.append(this.textElement("h2", copy.heading, "text-2xl font-semibold"))
      if (copy.body) block.append(this.textElement("p", copy.body, "mx-auto mt-3 max-w-2xl whitespace-pre-line text-stone-600"))
      if (["featured_collection", "collection_list"].includes(section.kind)) {
        const grid = document.createElement("div"); grid.className = "mt-6 grid grid-cols-3 gap-3"
        for (let i = 0; i < 3; i++) { const card = document.createElement("span"); card.className = "h-24 bg-stone-100"; grid.append(card) }
        block.append(grid)
      }
      if (copy.button_label) block.append(this.textElement("span", copy.button_label, "mt-5 inline-block bg-stone-900 px-4 py-2 text-sm text-white"))
      block.dataset.previewIndex = index
      this.previewTarget.append(block)
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
    if (!section) { this.settingsTitleTarget.textContent = "Section settings"; return }
    this.settingsTitleTarget.textContent = this.labelFor(section.kind)
    this.settingsFormTarget.append(this.checkboxField("Visible", "visible", section.visible !== false))
    section.translations ||= {}
    section.translations[this.locale] ||= {}
    ;(COPY_FIELDS[section.kind] || []).forEach(field => this.settingsFormTarget.append(this.textField(this.humanize(field), `translations.${this.locale}.${field}`, section.translations[this.locale][field] || "", field === "body")))
    section.settings ||= {}
    ;(SETTING_FIELDS[section.kind] || []).forEach(field => this.settingsFormTarget.append(this.textField(this.humanize(field), `settings.${field}`, section.settings[field] || "")))
    Array.from(this.settingsFormTarget.elements).forEach(element => { element.disabled = this.readOnlyValue })
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
    this.renderTree(); this.renderPreview(); this.updateHistoryButtons()
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

  remember() { this.undoStack.push(this.cloneSnapshot()); if (this.undoStack.length > 50) this.undoStack.shift(); this.redoStack = [] }
  undo() { if (!this.undoStack.length || this.readOnlyValue) return; this.redoStack.push(this.cloneSnapshot()); this.snapshot = this.undoStack.pop(); this.selectedIndex = Math.min(this.selectedIndex, this.snapshot.sections.length - 1); this.markUnsaved(); this.render() }
  redo() { if (!this.redoStack.length || this.readOnlyValue) return; this.undoStack.push(this.cloneSnapshot()); this.snapshot = this.redoStack.pop(); this.markUnsaved(); this.render() }
  changeLocale() { this.locale = this.localeTarget.value; this.renderPreview(); this.renderSettings() }
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
  labelFor(kind) { return ({ hero: "Image banner", ticker: "Scrolling text", featured_collection: "Featured collection", collection_list: "Collection list", image_with_text: "Image with text", rich_text: "Rich text" })[kind] || this.humanize(kind) }
  humanize(value) { return String(value || "").replaceAll("_", " ").replace(/^./, character => character.toUpperCase()) }
}
