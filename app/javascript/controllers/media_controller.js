import { Controller } from "@hotwired/stimulus"

// Admin media: drop files onto the upload zone (with previews) and drag
// existing images to reorder them. Each item carries a hidden input, so the
// DOM order is the submitted order.
export default class extends Controller {
  static targets = ["list", "item", "input", "zone", "previews", "selectionCount", "mainButton", "removeButton", "removals", "undoNotice", "viewer", "viewerImage"]

  connect() {
    this.pendingFiles = []
    this.selectionChanged()
  }

  selectedItems() {
    return this.itemTargets.filter(item => item.querySelector(".admin-media-select")?.checked)
  }

  selectionChanged() {
    if (!this.hasSelectionCountTarget) return
    const count = this.selectedItems().length
    this.selectionCountTarget.textContent = count ? `${count} selected` : "Drag to reorder. First image is featured."
    this.mainButtonTarget.disabled = count !== 1
    this.removeButtonTarget.disabled = count === 0
    this.itemTargets.forEach(item => item.classList.toggle("is-selected", Boolean(item.querySelector(".admin-media-select")?.checked)))
  }

  makeMain() {
    const item = this.selectedItems()[0]
    if (item) this.listTarget.prepend(item)
  }

  removeSelected() {
    this.removedItems = this.selectedItems().map(item => ({ item, index: this.itemTargets.indexOf(item) }))
    this.removedItems.forEach(({ item }) => {
      const input = document.createElement("input")
      input.type = "hidden"
      input.name = "product[remove_image_ids][]"
      input.value = item.querySelector('input[name="product[image_order][]"]').value
      this.removalsTarget.append(input)
      item.remove()
    })
    this.undoNoticeTarget.hidden = false
    this.selectionChanged()
  }

  undoRemove() {
    this.removedItems?.forEach(({ item, index }) => {
      const id = item.querySelector('input[name="product[image_order][]"]').value
      Array.from(this.removalsTarget.children).find(input => input.value === id)?.remove()
      item.querySelector(".admin-media-select").checked = false
      this.listTarget.insertBefore(item, this.listTarget.children[index] || null)
    })
    this.removedItems = []
    this.undoNoticeTarget.hidden = true
    this.selectionChanged()
  }

  preview(event) {
    const image = event.currentTarget.querySelector("img")
    this.viewerImageTarget.src = image.src
    this.viewerImageTarget.alt = image.alt
    this.previewOpener = event.currentTarget
    this.viewerTarget.showModal()
  }

  closePreview() {
    this.viewerTarget.close()
    this.previewOpener?.focus()
  }

  addFiles() {
    const files = new DataTransfer()
    const seen = new Set()
    ;[...this.pendingFiles, ...this.inputTarget.files].forEach(file => {
      const key = `${file.name}:${file.size}:${file.lastModified}`
      if (file.type.startsWith("image/") && !seen.has(key)) { files.items.add(file); seen.add(key) }
    })
    this.inputTarget.files = files.files
    this.renderPreviews()
  }

  // ——— Upload zone ———

  zoneOver(event) {
    if (this.dragged || !this.hasFiles(event)) return
    event.preventDefault()
    this.zoneTarget.classList.add("is-dragover")
  }

  zoneLeave() {
    this.zoneTarget.classList.remove("is-dragover")
  }

  zoneDrop(event) {
    if (this.dragged || !this.hasFiles(event)) return
    event.preventDefault()
    this.zoneLeave()

    const images = [...event.dataTransfer.files].filter((file) => file.type.startsWith("image/"))
    if (images.length === 0) return

    const files = new DataTransfer()
    if (this.inputTarget.multiple) {
      [...this.inputTarget.files].forEach((file) => files.items.add(file))
      images.forEach((file) => files.items.add(file))
    } else {
      files.items.add(images[0])
    }
    this.inputTarget.files = files.files
    this.renderPreviews()
  }

  renderPreviews() {
    if (!this.hasPreviewsTarget) return
    this.pendingFiles = [...this.inputTarget.files]

    this.previewsTarget.replaceChildren(...[...this.inputTarget.files].map((file, index) => {
      const item = document.createElement("li")
      item.className = "admin-media-item admin-media-item--pending"

      const thumb = document.createElement("img")
      thumb.src = URL.createObjectURL(file)
      thumb.alt = file.name
      thumb.onload = () => URL.revokeObjectURL(thumb.src)

      const remove = document.createElement("button")
      remove.type = "button"
      remove.className = "admin-media-item__btn"
      remove.textContent = "×"
      remove.title = `Don’t upload ${file.name}`
      remove.addEventListener("click", () => this.removePending(index))

      const bar = document.createElement("span")
      bar.className = "admin-media-item__bar"
      bar.append("New", remove)

      item.append(thumb, bar)
      return item
    }))
  }

  removePending(index) {
    const files = new DataTransfer()
    ;[...this.inputTarget.files].forEach((file, i) => { if (i !== index) files.items.add(file) })
    this.inputTarget.files = files.files
    this.renderPreviews()
  }

  hasFiles(event) {
    return [...(event.dataTransfer?.types || [])].includes("Files")
  }

  // ——— Reorder ———

  dragStart(event) {
    this.dragged = event.currentTarget
    event.dataTransfer.effectAllowed = "move"
    event.dataTransfer.setData("text/plain", "")
    requestAnimationFrame(() => this.dragged?.classList.add("is-dragging"))
  }

  dragOver(event) {
    if (!this.dragged) return
    event.preventDefault()

    const target = event.target.closest("[data-media-target='item']")
    if (!target || target === this.dragged) return

    const box = target.getBoundingClientRect()
    const after = event.clientX > box.left + box.width / 2
    this.listTarget.insertBefore(this.dragged, after ? target.nextSibling : target)
  }

  drop(event) {
    if (this.dragged) event.preventDefault()
  }

  dragEnd() {
    this.dragged?.classList.remove("is-dragging")
    this.dragged = null
  }

  moveEarlier(event) {
    const item = event.currentTarget.closest("[data-media-target='item']")
    if (item.previousElementSibling) this.listTarget.insertBefore(item, item.previousElementSibling)
    event.currentTarget.focus()
  }

  moveLater(event) {
    const item = event.currentTarget.closest("[data-media-target='item']")
    if (item.nextElementSibling) this.listTarget.insertBefore(item.nextElementSibling, item)
    event.currentTarget.focus()
  }
}
