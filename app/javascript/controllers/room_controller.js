import { Controller } from "@hotwired/stimulus"

// Soft parallax drift for room objects on mouse move
export default class extends Controller {
  static targets = ["object"]

  connect() {
    this.boundMove = this.onMove.bind(this)
    this.boundLeave = this.onLeave.bind(this)
    this.element.addEventListener("mousemove", this.boundMove)
    this.element.addEventListener("mouseleave", this.boundLeave)
  }

  disconnect() {
    this.element.removeEventListener("mousemove", this.boundMove)
    this.element.removeEventListener("mouseleave", this.boundLeave)
  }

  onMove(event) {
    const rect = this.element.getBoundingClientRect()
    const x = (event.clientX - rect.left) / rect.width - 0.5
    const y = (event.clientY - rect.top) / rect.height - 0.5

    this.objectTargets.forEach((el, index) => {
      const depth = 6 + (index % 3) * 4
      el.style.transform = `translate(${x * depth}px, ${y * depth}px)`
    })
  }

  onLeave() {
    this.objectTargets.forEach((el) => {
      el.style.transform = "translate(0, 0)"
    })
  }
}
