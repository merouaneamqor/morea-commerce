import { Controller } from "@hotwired/stimulus"

// Bulk image upload: matches each file to a product by its name
// ("essential-set-2.jpg" -> essential-set) and lets the admin fix the matches.
export default class extends Controller {
  static targets = ["input", "zone", "rows", "table", "summary", "submit"]
  static values = { products: Array }

  connect() {
    this.files = []
    this.choices = []
    this.render()
  }

  over(event) {
    if (![...(event.dataTransfer?.types || [])].includes("Files")) return
    event.preventDefault()
    this.zoneTarget.classList.add("is-dragover")
  }

  leave() {
    this.zoneTarget.classList.remove("is-dragover")
  }

  drop(event) {
    if (![...(event.dataTransfer?.types || [])].includes("Files")) return
    event.preventDefault()
    this.leave()
    this.add([...event.dataTransfer.files])
  }

  pick() {
    // The input now only holds the newly picked files; merge them with earlier ones
    this.add([...this.inputTarget.files])
  }

  add(files) {
    files.filter((file) => file.type.startsWith("image/")).forEach((file) => {
      this.files.push(file)
      this.choices.push(this.match(file.name)?.id ?? "")
    })
    this.sync()
  }

  remove(event) {
    const index = Number(event.currentTarget.dataset.index)
    this.files.splice(index, 1)
    this.choices.splice(index, 1)
    this.sync()
  }

  choose(event) {
    this.choices[Number(event.currentTarget.dataset.index)] = event.currentTarget.value
    this.summarize()
  }

  sync() {
    const transfer = new DataTransfer()
    this.files.forEach((file) => transfer.items.add(file))
    this.inputTarget.files = transfer.files
    this.render()
  }

  render() {
    this.tableTarget.classList.toggle("hidden", this.files.length === 0)
    this.rowsTarget.replaceChildren(...this.files.map((file, index) => this.row(file, index)))
    this.summarize()
  }

  row(file, index) {
    const tr = document.createElement("tr")

    const thumbCell = document.createElement("td")
    const thumb = document.createElement("img")
    thumb.className = "h-12 w-12 rounded-lg object-cover"
    thumb.src = URL.createObjectURL(file)
    thumb.onload = () => URL.revokeObjectURL(thumb.src)
    thumbCell.append(thumb)

    const nameCell = document.createElement("td")
    nameCell.className = "admin-muted break-all"
    nameCell.textContent = file.name

    const selectCell = document.createElement("td")
    const select = document.createElement("select")
    select.name = "product_ids[]"
    select.className = "admin-input"
    select.dataset.index = index
    select.dataset.action = "bulk-upload#choose"
    select.append(new Option("— Skip this image —", ""))
    this.productsValue.forEach((product) => select.append(new Option(product.name, product.id)))
    select.value = String(this.choices[index])
    selectCell.append(select)

    const removeCell = document.createElement("td")
    const remove = document.createElement("button")
    remove.type = "button"
    remove.className = "admin-media-item__btn"
    remove.textContent = "×"
    remove.title = `Don’t upload ${file.name}`
    remove.dataset.index = index
    remove.dataset.action = "bulk-upload#remove"
    removeCell.append(remove)

    tr.append(thumbCell, nameCell, selectCell, removeCell)
    return tr
  }

  summarize() {
    const assigned = this.choices.filter((id) => id !== "")
    const products = new Set(assigned).size
    const skipped = this.files.length - assigned.length
    this.submitTarget.disabled = assigned.length === 0
    this.submitTarget.textContent = assigned.length ? `Upload ${assigned.length} to ${products} product${products === 1 ? "" : "s"}` : "Upload"
    this.summaryTarget.textContent = this.files.length === 0 ? "" :
      `${this.files.length} image${this.files.length === 1 ? "" : "s"}` + (skipped ? ` · ${skipped} without a product will be skipped` : "")
  }

  // Longest product slug (or name) the file name starts with, ignoring "-2", "_03", " (1)"
  match(filename) {
    const base = this.normalize(filename.replace(/\.[^.]+$/, ""))
    const stem = base.replace(/(-(\d+|copy))+$/, "")
    let best = null
    this.productsValue.forEach((product) => {
      ;[this.normalize(product.slug), this.normalize(product.name)].forEach((key) => {
        if (!key) return
        const hit = stem === key || base === key || base.startsWith(`${key}-`)
        if (hit && (!best || key.length > best.length)) best = { id: product.id, length: key.length }
      })
    })
    return best
  }

  normalize(value) {
    return String(value || "")
      .normalize("NFD").replace(/[̀-ͯ]/g, "")
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-+|-+$/g, "")
  }
}
