import assert from "node:assert/strict"
import fs from "node:fs/promises"
import { existsSync } from "node:fs"
import http from "node:http"
import path from "node:path"
import { chromium } from "playwright"

// Component fixture: real logo partial/CSS/controller and vendored Three.js.
// A minimal Controller base supplies Stimulus targets/values explicitly; this
// checks rendering and lifecycle, not Rails routes or Stimulus auto-discovery.
const root = process.cwd()
const output = path.join(root, "tmp/morea-logo")
await fs.mkdir(output, { recursive: true })
const mappings = {
  three: "/vendor/three.module.min.js",
  "three/core": "/vendor/three.core.min.js",
  "three/addons/geometries/TextGeometry.js": "/vendor/three-TextGeometry.js",
  "three/addons/loaders/FontLoader.js": "/vendor/three-FontLoader.js",
  "morea-typeface": "/vendor/morea-typeface.js"
}
const server = http.createServer(async (request, response) => {
  try {
    const url = new URL(request.url, "http://localhost")
    if (url.pathname === "/") {
      const partial = (await fs.readFile("app/views/home/sections/_morea_logo.html.erb", "utf8")).replace(/<%#[\s\S]*?%>/g, "")
      response.setHeader("Content-Type", "text/html")
      response.end(`<!doctype html><html dir="${url.searchParams.get("dir") === "rtl" ? "rtl" : "ltr"}"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><link rel="stylesheet" href="/style.css"><style>*,*::before,*::after{box-sizing:border-box}html,body{margin:0}body{font:16px Arial}.campaign-hero{padding:32px 24px;background:#272322;color:#fff;min-height:100vh}.copy{max-width:600px}h1{font-size:32px;overflow-wrap:anywhere}button{padding:16px 24px;cursor:pointer}footer{height:2000px}</style><script type="importmap">${JSON.stringify({ imports: mappings })}</script></head><body class="storefront-body"><section class="campaign-hero">${partial}<div class="copy"><h1>Nouvelle collection Morea</h1><p>Des essentiels pour chaque mouvement.</p><button id="shop">Découvrir la collection</button></div></section><footer></footer><script type="module">import Logo from '/controller.js'; const element=document.querySelector('.campaign-hero__logo'); const controller=new Logo();controller.element=element;Object.defineProperty(controller,'canvasTarget',{get:()=>element.querySelector('canvas')});Object.defineProperty(controller,'hasCanvasTarget',{get:()=>!!element.querySelector('canvas')});controller.toneValue=new URL(location).searchParams.get('tone')||'ivory';window.logo=controller;window.clicked=0;document.querySelector('#shop').onclick=()=>window.clicked++;if(new URL(location).searchParams.get('tone')==='ink'){document.querySelector('.campaign-hero').style.background='#fff';document.querySelector('.campaign-hero').style.color='#111';element.dataset.heroAtmosphereToneValue='ink'}controller.connect();window.fixtureReady=true;</script></body></html>`)
    } else if (url.pathname === "/controller.js") {
      response.setHeader("Content-Type", "text/javascript")
      response.end((await fs.readFile("app/javascript/controllers/hero_atmosphere_controller.js", "utf8")).replace('import { Controller } from "@hotwired/stimulus"', "class Controller {}"))
    } else if (url.pathname === "/style.css") {
      response.setHeader("Content-Type", "text/css")
      response.end(await fs.readFile("app/assets/stylesheets/storefront_responsive.css"))
    } else if (Object.values(mappings).includes(url.pathname)) {
      response.setHeader("Content-Type", "text/javascript")
      response.end(await fs.readFile(path.join(root, "vendor/javascript", path.basename(url.pathname))))
    } else { response.writeHead(404); response.end() }
  } catch (error) { response.writeHead(500); response.end(String(error)) }
})
await new Promise(resolve => server.listen(0, "127.0.0.1", resolve))
const base = `http://127.0.0.1:${server.address().port}`
const browser = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || (existsSync("/usr/bin/chromium") ? "/usr/bin/chromium" : undefined), headless: true, args: ["--no-sandbox", "--enable-unsafe-swiftshader", "--use-angle=swiftshader"] })
const results = []
const failures = []
async function check(name, action) {
  if (process.env.LOGO_CHECK && !name.includes(process.env.LOGO_CHECK)) return
  try { await action(); results.push({ name, passed: true }); console.log(`PASS ${name}`) }
  catch (error) { failures.push({ name, error: String(error) }); console.error(`FAIL ${name}: ${error}`) }
}
async function fixture(options = {}, query = "") {
  const context = await browser.newContext({ reducedMotion: "no-preference", ...options })
  const page = await context.newPage()
  page.errors = []
  page.on("pageerror", error => { page.errors.push(String(error)); console.error("Browser error:", String(error)) })
  await page.goto(base + "/" + query)
  await page.waitForFunction(() => window.fixtureReady)
  return { context, page }
}
async function ready(page) {
  await page.waitForFunction(() => document.querySelector(".campaign-hero__logo").dataset.heroAtmosphereState === "ready")
}
try {
  for (const width of [320, 375, 768, 1440]) for (const dir of ["ltr", "rtl"]) {
    await check(`geometry/render/CTA ${width}px ${dir}`, async () => {
      const { context, page } = await fixture({ viewport: { width, height: 900 }, isMobile: width <= 375, hasTouch: width <= 375 }, `?dir=${dir}`)
      try {
        await ready(page)
        const geometry = await page.evaluate(() => {
          const logo = document.querySelector(".campaign-hero__logo").getBoundingClientRect()
          const copy = document.querySelector(".copy").getBoundingClientRect()
          const canvas = document.querySelector("canvas")
          window.logo.renderer.render(window.logo.scene, window.logo.camera)
          const gl = canvas.getContext("webgl2")
          const pixels = new Uint8Array(gl.drawingBufferWidth * gl.drawingBufferHeight * 4)
          gl.readPixels(0, 0, gl.drawingBufferWidth, gl.drawingBufferHeight, gl.RGBA, gl.UNSIGNED_BYTE, pixels)
          let painted = 0
          for (let i = 3; i < pixels.length; i += 4) if (pixels[i] > 0) painted++
          return { overflow: document.documentElement.scrollWidth > innerWidth, left: logo.left, right: logo.right, bottom: logo.bottom, copyTop: copy.top, painted }
        })
        assert.equal(geometry.overflow, false)
        assert.ok(geometry.left >= 0 && geometry.right <= width)
        assert.ok(geometry.bottom <= geometry.copyTop)
        assert.ok(geometry.painted > 100, `empty WebGL frame: ${JSON.stringify(geometry)}`)
        await page.locator("#shop").click()
        assert.equal(await page.evaluate(() => window.clicked), 1)
        assert.deepEqual(page.errors, [])
        if (width === 1440 && dir === "ltr") {
          await page.waitForTimeout(750)
          await page.screenshot({ path: path.join(output, "hero-dark.png") })
        }
      } finally { await context.close() }
    })
  }
  await check("black logo on white studio", async () => {
    const { context, page } = await fixture({ viewport: { width: 1440, height: 900 } }, "?tone=ink")
    try {
      await ready(page)
      const rgb = await page.evaluate(() => window.logo.material.color.toArray())
      assert.ok(rgb.every(value => value < 0.1), `ink material is not dark: ${rgb}`)
      await page.waitForTimeout(750)
      await page.screenshot({ path: path.join(output, "studio-ink.png") })
      await page.setViewportSize({ width: 637, height: 426 })
      await page.addStyleTag({content: '.copy,footer{display:none}.campaign-hero{padding:0;min-height:426px;display:flex;align-items:center;justify-content:center}.storefront-body .campaign-hero__logo{width:510px;height:150px;margin:0}'})
      await page.waitForTimeout(750)
      await page.screenshot({ path: path.join(output, "morea-logo-preview.png") })
    } finally { await context.close() }
  })
  for (const preference of ["reduce", "saveData", "noWebGL"]) await check(`${preference} static fallback`, async () => {
    const context = await browser.newContext({ reducedMotion: preference === "reduce" ? "reduce" : "no-preference" })
    const page = await context.newPage()
    let imports = 0
    let contexts = 0
    page.on("request", request => { if (request.url().includes("/vendor/")) imports++ })
    await page.exposeFunction("recordContext", () => contexts++)
    await page.addInitScript(preference => {
      if (preference === "saveData") Object.defineProperty(navigator, "connection", { value: { saveData: true } })
      const original = HTMLCanvasElement.prototype.getContext
      HTMLCanvasElement.prototype.getContext = function (...args) {
        if (String(args[0]).includes("webgl")) {
          window.recordContext()
          if (preference === "noWebGL") return null
        }
        return original.apply(this, args)
      }
    }, preference)
    try {
      await page.goto(base)
      await page.waitForFunction(() => window.fixtureReady)
      if (preference === "noWebGL") await page.waitForFunction(() => window.logo.failed)
      else await page.waitForTimeout(1200)
      assert.equal(await page.locator(".campaign-hero__logo-fallback").evaluate(element => getComputedStyle(element).opacity), "1")
      assert.equal(await page.evaluate(() => window.logo.renderer == null), true)
      if (preference !== "noWebGL") { assert.equal(imports, 0); assert.equal(contexts, 0) }
    } finally { await context.close() }
  })
  await check("ink fallback stays dark and titlecase in reduced motion RTL", async () => {
    const { context, page } = await fixture({ reducedMotion: "reduce" }, "?tone=ink&dir=rtl")
    try {
      const fallback = page.locator(".campaign-hero__logo-fallback")
      assert.equal(await fallback.textContent(), "Morea")
      assert.equal(await fallback.getAttribute("dir"), "ltr")
      assert.equal(await fallback.evaluate(element => getComputedStyle(element).color), "rgb(21, 21, 21)")
      assert.equal(await page.evaluate(() => window.logo.renderer == null), true)
    } finally { await context.close() }
  })
  await check("offscreen and hidden pause; Turbo disposes", async () => {
    const { context, page } = await fixture()
    try {
      await ready(page)
      await page.evaluate(() => window.scrollTo(0, 1400))
      await page.waitForFunction(() => !window.logo.visible && window.logo.frame == null)
      await page.evaluate(() => window.scrollTo(0, 0))
      await page.waitForFunction(() => window.logo.visible && window.logo.frame != null)
      await page.evaluate(() => { Object.defineProperty(document, "visibilityState", { configurable: true, value: "hidden" }); document.dispatchEvent(new Event("visibilitychange")) })
      assert.equal(await page.evaluate(() => window.logo.frame), null)
      await page.evaluate(() => { Object.defineProperty(document, "visibilityState", { configurable: true, value: "visible" }); document.dispatchEvent(new Event("visibilitychange")) })
      await page.waitForFunction(() => window.logo.frame != null)
      const cleaned = await page.evaluate(() => {
        const counts = { geometry: 0, material: 0, rendererDisposed: 0 }
        for (const geometry of window.logo.geometries) geometry.addEventListener("dispose", () => counts.geometry++)
        window.logo.material.addEventListener("dispose", () => counts.material++)
        const renderer = window.logo.renderer
        const dispose = renderer.dispose.bind(renderer)
        renderer.dispose = () => { counts.rendererDisposed++; dispose() }
        document.dispatchEvent(new Event("turbo:before-cache"))
        return { ...counts, connected: window.logo.connected, renderer: window.logo.renderer, frame: window.logo.frame, state: window.logo.element.dataset.heroAtmosphereState }
      })
      assert.deepEqual(cleaned, { geometry: 2, material: 1, rendererDisposed: 1, renderer: null, frame: null, connected: false, state: "idle" })
      assert.deepEqual(page.errors, [])
    } finally { await context.close() }
  })
  await check("motion change events dispose and recreate the scene", async () => {
    const { context, page } = await fixture()
    try {
      await ready(page)
      await page.evaluate(() => { window.originalCanvas = window.logo.canvasTarget })
      await page.emulateMedia({ reducedMotion: "reduce" })
      // Chromium CDP media changes can update matches without emitting change.
      // Deliver the browser event explicitly to test the registered handler.
      await page.evaluate(() => window.logo.motion.dispatchEvent(new Event("change")))
      await page.waitForFunction(() => window.logo.renderer == null && window.logo.frame == null)
      assert.equal(await page.evaluate(() => window.logo.element.dataset.heroAtmosphereState), "idle")
      await page.emulateMedia({ reducedMotion: "no-preference" })
      await page.evaluate(() => window.logo.motion.dispatchEvent(new Event("change")))
      await ready(page)
      assert.equal(await page.evaluate(() => window.logo.canvasTarget !== window.originalCanvas), true)
      assert.deepEqual(page.errors, [])
    } finally { await context.close() }
  })
  await check("disconnect while module import is pending", async () => {
    const context = await browser.newContext()
    const page = await context.newPage()
    let release
    const gate = new Promise(resolve => { release = resolve })
    await page.route("**/vendor/three.module.min.js", async route => { await gate; await route.continue() })
    try {
      await page.goto(base)
      await page.waitForFunction(() => window.logo?.importing)
      await page.evaluate(() => window.logo.disconnect())
      release()
      await page.waitForTimeout(700)
      assert.equal(await page.evaluate(() => window.logo.renderer == null && !window.logo.connected && window.logo.frame == null), true)
    } finally { release(); await context.close() }
  })
} finally {
  await browser.close()
  await new Promise(resolve => server.close(resolve))
  await fs.writeFile(path.join(output, "results.json"), JSON.stringify({ mode: "component fixture with manual Stimulus targets", checks: results.length + failures.length, results, failures }, null, 2))
}
console.log(`${results.length} passed; ${failures.length} failed`)
if (failures.length) process.exitCode = 1
