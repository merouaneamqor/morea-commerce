import { Controller } from "@hotwired/stimulus"

// Admin media: drop files onto the upload zone (with previews) and drag
// existing images to reorder them. Each item carries a hidden input, so the
// DOM order is the submitted order.
export default class extends Controller {
  static targets = ["list", "item", "input", "zone", "previews"]

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
