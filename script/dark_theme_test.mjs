// Computed CSS regression checks; these fixtures exercise shared theme components, not Rails routes.
import assert from "node:assert/strict"
import { readFileSync, existsSync, mkdirSync, writeFileSync } from "node:fs"
import { resolve } from "node:path"
import { chromium } from "playwright"
const root = resolve(import.meta.dirname, "..")
const cssPath = resolve(root, process.env.RESPONSIVE_TAILWIND || "tmp/responsive-tailwind.css")
assert.ok(existsSync(cssPath), "Run npm run build:test-css first")
const css = [cssPath, ...["application", "admin_pwa", "liquid_glass", "admin_responsive"].map(name => resolve(root, `app/assets/stylesheets/${name}.css`))].map(path => readFileSync(path, "utf8")).join("\n")
const darkCss = readFileSync(resolve(root, "app/assets/stylesheets/admin_dark.css"), "utf8")
// Utility classes below are the current shell, accounting, date picker and order-form contracts.
const markup = `<div data-seller-shell class="min-h-dvh bg-[#f3f1ef] text-[#5e5a58] p-4">
  <nav data-probe="sidebar" class="rounded-2xl border border-[#e8e3df] bg-white p-3"><a data-probe="nav" class="text-[#5e5a58] hover:bg-[#f3f1ef]">Commandes</a><a data-probe="selected" class="bg-[#f4e4de] text-[#a8432e] p-2">Comptabilité</a></nav>
  <div class="bg-[#1f2430] p-3 text-white"><button data-probe="translucent" class="bg-white/10 text-white p-2">Exporter</button></div>
  <main class="admin-page seller-page">
    <section data-probe="card" class="rounded-xl border border-[#e8e3df] bg-white p-4">
      <h1 data-probe="heading" class="text-[#1f2430]">Comptabilité</h1><p data-probe="muted" class="text-[#8a8380]">Toutes les commandes de ce mois</p>
      <label data-probe="label" class="text-[#5e5a58]">Nom<input data-probe="input" class="admin-input" placeholder="Nom du client" value="Synthetic buyer"></label>
      <select data-probe="select" class="admin-input"><option>Casablanca</option></select>
      <button data-probe="primary" class="admin-btn">Enregistrer</button><button data-probe="secondary" class="admin-btn-secondary">Annuler</button>
      <div class="admin-table-wrap"><table class="admin-table"><thead><tr><th data-probe="table-head">Commandes</th></tr></thead><tbody><tr><td data-probe="table-cell" class="text-[#1f2430]">123 MAD</td></tr></tbody></table></div>
      <div data-probe="success" class="admin-banner admin-banner--success">Commande enregistrée</div><div data-probe="critical" class="admin-banner admin-banner--critical">Erreur de validation</div>
      <span data-probe="badge" class="admin-badge admin-badge--info">Confirmée</span>
      <div data-probe="utility-success" class="bg-[#e3f3e8] text-[#2f7a4a] p-3">Modification enregistrée</div>
      <div data-probe="utility-warning" class="bg-[#fcf0dc] text-[#9a6412] p-3">Pointer l’arrivée</div>
    </section>
    <div data-controller="date-range-picker"><div data-probe="calendar" data-date-range-picker-target="panel" class="rounded-2xl border border-[#e8e3df] bg-white p-3 text-[#1f2430]"><p data-probe="calendar-label" class="text-[#8a8380]">Date de début</p><button data-probe="calendar-day" class="text-[#1f2430]">15</button><button data-probe="calendar-selected" class="bg-[#a8432e] text-white p-2">16</button></div></div>
    <div data-probe="glass" class="lg-panel rounded-2xl p-4"><p data-probe="glass-text" class="text-[#1f2430]">Intégrations API</p></div>
  </main>
</div>`
const browser = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || (existsSync("/usr/bin/chromium") ? "/usr/bin/chromium" : undefined), headless: true, args: ["--no-sandbox"] })
const results = [], failures = []
async function samples(page) {
  return page.evaluate(() => {
    const canvas = document.createElement("canvas"), ctx = canvas.getContext("2d", { willReadFrequently: true })
    function rgba(value) { ctx.clearRect(0,0,1,1); ctx.fillStyle=value; ctx.fillRect(0,0,1,1); return [...ctx.getImageData(0,0,1,1).data].map((v,i)=>i===3?v/255:v) }
    function mix(top,bottom) { const a=top[3]; return top.slice(0,3).map((v,i)=>v*a+bottom[i]*(1-a)).concat(1) }
    function background(el) {
      const parent=el.parentElement ? background(el.parentElement) : [255,255,255,1], style=getComputedStyle(el)
      const solid=mix(rgba(style.backgroundColor),parent)
      const stop=style.backgroundImage.match(/rgba?\([^)]*\)/)
      return stop ? mix(rgba(stop[0]),solid) : solid
    }
    function lum(rgb) { const c=rgb.slice(0,3).map(v=>{ v/=255; return v<=.04045?v/12.92:((v+.055)/1.055)**2.4 });return c[0]*.2126+c[1]*.7152+c[2]*.0722 }
    return Object.fromEntries([...document.querySelectorAll("[data-probe], [data-seller-shell]")].map(el=>{
      const style=getComputedStyle(el), bg=background(el), fg=mix(rgba(style.color),bg), a=lum(fg),b=lum(bg)
      return [el.dataset.probe || "shell", { color:style.color, background:style.backgroundColor, image:style.backgroundImage, border:style.borderColor, luminance:b, contrast:(Math.max(a,b)+.05)/(Math.min(a,b)+.05), scheme:style.colorScheme }]
    }))
  })
}
try {
  for (const [width,height] of [[375,812],[1440,900]]) for (const dir of ["ltr","rtl"]) {
    const page=await browser.newPage({viewport:{width,height}})
    await page.setContent(`<!doctype html><html dir="${dir}"><head><style>${css}</style></head><body class="admin-body" data-admin-theme="seallo">${markup}</body></html>`)
    const baseline=await samples(page)
    await page.addStyleTag({content:darkCss})
    assert.deepEqual(await samples(page),baseline,"Dark stylesheet must not change light Seallo computed styles")
    await page.locator("body").evaluate(el=>el.dataset.adminTheme="seallo_dark")
    await page.evaluate(() => Promise.all(document.getAnimations().map(animation => animation.finished.catch(() => {}))))
    const dark=await samples(page)
    assert.equal(dark.translucent.background, baseline.translucent.background, "Translucent white header controls must retain their alpha rather than become opaque cards")
    for (const name of ["shell","sidebar","card","input","select","calendar","table-head","table-cell","glass","utility-success","utility-warning"]) {
      if(dark[name].luminance>=.12) failures.push({width,dir,name,reason:"light surface in dark theme",sample:dark[name]})
    }
    for(const [name,sample] of Object.entries(dark)) {
      if(sample.contrast<4.5) failures.push({width,dir,name,reason:"text contrast below 4.5:1",sample})
    }
    if(!dark.input.scheme.includes("dark")) failures.push({width,dir,name:"input",reason:"native control is not dark"})
    await page.locator('[data-probe="nav"]').hover()
    await page.evaluate(() => Promise.all(document.getAnimations().map(animation => animation.finished.catch(() => {}))))
    const hovered=(await samples(page)).nav
    if(hovered.luminance>=.12 || hovered.contrast<4.5) failures.push({width,dir,name:"nav:hover",reason:"hover leaves dark readable palette",sample:hovered})
    results.push({width,height,dir,components:Object.keys(dark).length,dark})
    await page.close()
  }
} finally {await browser.close()}
mkdirSync(resolve(root,"tmp"),{recursive:true})
writeFileSync(resolve(root,"tmp/dark-theme-results.json"),JSON.stringify({mode:"component-fixtures",results,failures},null,2))
assert.deepEqual(failures,[],JSON.stringify(failures,null,2))
console.log(`Dark Seallo: ${results.length} mobile/desktop LTR/RTL cases passed; ${results[0].components} component colors/contrast checks each; light theme unchanged`)
