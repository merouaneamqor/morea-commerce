import { Controller } from "@hotwired/stimulus"

// Decorative wordmark only. The ordinary text remains the fallback while this
// waits for the page, visibility and the visitor's motion/data preferences.
export default class extends Controller {
  static targets = ["canvas"]
  static values = { tone: { type: String, default: "ivory" } }

  connect() {
    if (!this.hasCanvasTarget) return

    this.connected = true
    this.generation = (this.generation || 0) + 1
    this.failed = false
    const generation = this.generation
    this.visible = false
    this.loaded = document.readyState === "complete"
    this.elapsed = 0
    this.pointer = { x: 0, y: 0 }
    this.pointerTarget = { x: 0, y: 0 }
    this.motion = window.matchMedia("(prefers-reduced-motion: reduce)")
    this.finePointer = window.matchMedia("(hover: hover) and (pointer: fine)")
    this.connection = navigator.connection
    this.pointerSurface = this.element.closest(".campaign-hero") || this.element
    this.setState("idle")

    this.onPreference = () => {
      if (!this.connected) return
      if (!this.eligible()) {
        this.cancelDeferred()
        this.disposeScene()
        this.setState("idle")
      } else {
        this.queueStart()
      }
    }
    this.onVisibility = () => this.queueStart()
    this.onLoad = () => {
      if (!this.connected || generation !== this.generation) return
      this.loaded = true
      this.queueStart()
    }
    this.onBeforeCache = () => this.disconnect()
    this.onPointer = (event) => {
      if (!this.connected || !this.finePointer.matches) return
      const bounds = this.pointerSurface.getBoundingClientRect()
      if (!bounds.width || !bounds.height) return
      this.pointerTarget.x = Math.max(-1, Math.min(1, (event.clientX - bounds.left) / bounds.width * 2 - 1))
      this.pointerTarget.y = Math.max(-1, Math.min(1, (event.clientY - bounds.top) / bounds.height * 2 - 1))
    }
    this.onPointerLeave = () => { this.pointerTarget = { x: 0, y: 0 } }
    this.onPointerPreference = () => this.updatePointerListeners()
    this.motion.addEventListener("change", this.onPreference)
    this.connection?.addEventListener?.("change", this.onPreference)
    this.finePointer.addEventListener("change", this.onPointerPreference)
    document.addEventListener("visibilitychange", this.onVisibility)
    document.addEventListener("turbo:before-cache", this.onBeforeCache)
    if (!this.loaded) window.addEventListener("load", this.onLoad, { once: true })
    this.updatePointerListeners()

    if ("IntersectionObserver" in window) {
      this.intersection = new IntersectionObserver((entries) => {
        if (!this.connected || generation !== this.generation) return
        this.visible = entries.some((entry) => entry.isIntersecting && entry.intersectionRatio > 0)
        this.queueStart()
      }, { threshold: 0.01 })
      this.intersection.observe(this.element)
    } else {
      this.visible = true
      this.queueStart()
    }
  }

  disconnect() {
    if (!this.connected) return
    this.connected = false
    this.generation += 1
    this.cancelDeferred()
    this.intersection?.disconnect()
    this.intersection = null
    this.motion?.removeEventListener("change", this.onPreference)
    this.connection?.removeEventListener?.("change", this.onPreference)
    this.finePointer?.removeEventListener("change", this.onPointerPreference)
    document.removeEventListener("visibilitychange", this.onVisibility)
    document.removeEventListener("turbo:before-cache", this.onBeforeCache)
    window.removeEventListener("load", this.onLoad)
    this.removePointerListeners()
    this.disposeScene()
    this.importing = false
    this.modules = null
    this.setState("idle")
  }

  eligible() {
    return this.connected && !this.failed && !this.motion.matches && !this.connection?.saveData
  }

  canRun() {
    return this.eligible() && this.visible && document.visibilityState !== "hidden"
  }

  setState(state) {
    this.element.dataset.heroAtmosphereState = state
  }

  updatePointerListeners() {
    this.removePointerListeners()
    if (!this.connected || !this.finePointer.matches) return
    this.pointerSurface.addEventListener("pointermove", this.onPointer, { passive: true })
    this.pointerSurface.addEventListener("pointerleave", this.onPointerLeave, { passive: true })
  }

  removePointerListeners() {
    this.pointerSurface?.removeEventListener("pointermove", this.onPointer)
    this.pointerSurface?.removeEventListener("pointerleave", this.onPointerLeave)
    if (this.pointerTarget) this.pointerTarget = { x: 0, y: 0 }
  }

  queueStart() {
    if (!this.canRun()) {
      this.cancelDeferred()
      this.stopAnimation()
      return
    }
    if (!this.loaded) return
    if (this.renderer) {
      this.startAnimation()
      return
    }
    if (this.deferred != null || this.importing) return

    const generation = this.generation
    const start = () => {
      this.deferred = null
      if (generation !== this.generation || !this.canRun()) return
      this.loadScene(generation)
    }
    this.idleCallback = "requestIdleCallback" in window
    this.deferred = this.idleCallback ? window.requestIdleCallback(start, { timeout: 1000 }) : window.setTimeout(start, 150)
  }

  cancelDeferred() {
    if (this.deferred == null) return
    if (this.idleCallback) window.cancelIdleCallback(this.deferred)
    else window.clearTimeout(this.deferred)
    this.deferred = null
  }

  async loadScene(generation) {
    this.importing = true
    try {
      const modules = this.modules || await Promise.all([
        import("three"),
        import("three/addons/geometries/TextGeometry.js"),
        import("three/addons/loaders/FontLoader.js"),
        import("morea-typeface")
      ])
      if (generation !== this.generation || !this.connected) return
      this.modules = modules
      if (!this.canRun()) return
      this.buildScene(...modules)
      this.startAnimation()
    } catch {
      if (generation !== this.generation || !this.connected) return
      this.failed = true
      this.disposeScene()
      this.setState("fallback")
    } finally {
      if (generation === this.generation) this.importing = false
    }
  }

  buildScene(THREE, { TextGeometry }, { FontLoader }, typeface) {
    this.renderer = new THREE.WebGLRenderer({
      canvas: this.canvasTarget, alpha: true, antialias: true,
      powerPreference: "low-power", depth: true, stencil: false, precision: "mediump"
    })
    this.renderer.setClearColor(0x000000, 0)
    this.renderer.outputColorSpace = THREE.SRGBColorSpace
    this.scene = new THREE.Scene()
    this.camera = new THREE.OrthographicCamera(-1, 1, 1, -1, 0.1, 30)
    this.camera.position.z = 10
    const loader = new FontLoader()
    const options = {
      size: 1, depth: 0.08, curveSegments: 4,
      bevelEnabled: true, bevelThickness: 0.012, bevelSize: 0.008, bevelSegments: 1, steps: 1
    }
    this.geometries = []
    const initial = new TextGeometry("M", { ...options, font: loader.parse(typeface.default.sans) })
    this.geometries.push(initial)
    const suffix = new TextGeometry("orea", { ...options, size: 1.23, font: loader.parse(typeface.default.serif) })
    this.geometries.push(suffix)
    initial.computeBoundingBox()
    suffix.computeBoundingBox()
    suffix.translate(initial.boundingBox.max.x - suffix.boundingBox.min.x + 0.12, 0, 0)
    const finish = this.toneValue === "ink"
      ? { color: 0x151515, metalness: 0.2, roughness: 0.35 }
      : { color: 0xeadfc9, metalness: 0.58, roughness: 0.32 }
    this.material = new THREE.MeshStandardMaterial(finish)
    this.wordmark = new THREE.Group()
    this.wordmark.add(new THREE.Mesh(initial, this.material), new THREE.Mesh(suffix, this.material))
    const bounds = new THREE.Box3().setFromObject(this.wordmark)
    const center = bounds.getCenter(new THREE.Vector3())
    this.logoSize = bounds.getSize(new THREE.Vector3())
    this.geometries.forEach((geometry) => geometry.translate(-center.x, -center.y, -center.z))
    this.scene.add(this.wordmark)
    this.scene.add(new THREE.AmbientLight(0xfff5e5, 1.8))
    this.keyLight = new THREE.DirectionalLight(0xffe6bc, 3.2)
    this.keyLight.position.set(-3, 4, 6)
    this.scene.add(this.keyLight)
    const fill = new THREE.DirectionalLight(0xffffff, 2)
    fill.position.set(4, -1, 4)
    this.scene.add(fill)

    this.onContextLost = (event) => {
      event.preventDefault()
      if (!this.connected) return
      this.failed = true
      this.disposeScene()
      this.setState("fallback")
    }
    this.canvasTarget.addEventListener("webglcontextlost", this.onContextLost)
    this.onResize = () => {
      if (this.connected && this.renderer) this.resize()
    }
    if ("ResizeObserver" in window) {
      this.resizeObserver = new ResizeObserver(this.onResize)
      this.resizeObserver.observe(this.element)
    } else {
      window.addEventListener("resize", this.onResize, { passive: true })
    }
    this.resize()
  }

  resize() {
    const { width, height } = this.canvasTarget.getBoundingClientRect()
    if (!width || !height) return
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 1.5))
    this.renderer.setSize(width, height, false)
    const aspect = width / height
    const span = Math.max(this.logoSize.x * 1.17, this.logoSize.y * 1.22 * aspect)
    this.camera.left = -span / 2
    this.camera.right = span / 2
    this.camera.top = span / aspect / 2
    this.camera.bottom = -span / aspect / 2
    this.camera.updateProjectionMatrix()
  }

  startAnimation() {
    if (this.frame != null || !this.renderer || !this.canRun()) return
    this.lastFrame = null
    this.frame = window.requestAnimationFrame((timestamp) => this.animate(timestamp))
  }

  animate(timestamp) {
    this.frame = null
    if (!this.renderer || !this.canRun()) return
    if (this.lastFrame == null || timestamp - this.lastFrame >= 1000 / 30) {
      this.elapsed += this.lastFrame == null ? 0 : Math.min((timestamp - this.lastFrame) / 1000, 0.06)
      this.lastFrame = timestamp
      this.pointer.x += (this.pointerTarget.x - this.pointer.x) * 0.06
      this.pointer.y += (this.pointerTarget.y - this.pointer.y) * 0.06
      this.wordmark.rotation.set(
        -0.07 + Math.sin(this.elapsed * 0.22) * 0.018 + this.pointer.y * 0.03,
        -0.08 + Math.sin(this.elapsed * 0.18) * 0.025 + this.pointer.x * 0.06,
        -0.012
      )
      this.wordmark.position.y = Math.sin(this.elapsed * 0.3) * this.logoSize.y * 0.025
      this.keyLight.position.x = -3 + Math.sin(this.elapsed * 0.16)
      try {
        this.renderer.render(this.scene, this.camera)
        this.setState("ready")
      } catch {
        this.failed = true
        this.disposeScene()
        this.setState("fallback")
        return
      }
    }
    this.frame = window.requestAnimationFrame((next) => this.animate(next))
  }

  stopAnimation() {
    if (this.frame != null) window.cancelAnimationFrame(this.frame)
    this.frame = null
    this.lastFrame = null
  }

  disposeScene() {
    this.stopAnimation()
    this.resizeObserver?.disconnect()
    this.resizeObserver = null
    if (this.onResize) window.removeEventListener("resize", this.onResize)
    if (this.onContextLost && this.hasCanvasTarget) this.canvasTarget.removeEventListener("webglcontextlost", this.onContextLost)
    this.geometries?.forEach((geometry) => geometry.dispose())
    this.material?.dispose()
    const canvas = this.renderer?.domElement
    this.renderer?.dispose()
    this.renderer?.forceContextLoss()
    // A lost WebGL context belongs to its canvas. A fresh target lets a later
    // preference change or Turbo restoration start without reviving old GPU state.
    if (canvas) canvas.replaceWith(canvas.cloneNode(false))
    this.renderer = this.scene = this.camera = this.geometries = this.material = this.wordmark = this.keyLight = this.logoSize = null
  }
}
