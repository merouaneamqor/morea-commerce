// Browser geometry checks. See docs/responsive-validation.md for setup and live mode.
import assert from "node:assert/strict"
import { readFileSync, existsSync, mkdirSync, writeFileSync } from "node:fs"
import { resolve } from "node:path"
const { chromium } = await import(process.env.PLAYWRIGHT_MODULE || "playwright")
const root = resolve(import.meta.dirname, "..")
const cssPath = process.env.RESPONSIVE_TAILWIND || resolve(root, "app/assets/builds/tailwind.css")
assert.ok(existsSync(cssPath), "Build Tailwind first; set RESPONSIVE_TAILWIND to the compiled CSS path")
const styles = [cssPath, ...["application", "admin_pwa", "platform_home", "seallo_connect_pages", "storefront_responsive", "admin_responsive", "auth_responsive"].map(name => resolve(root, `app/assets/stylesheets/${name}.css`))]
for (const path of styles) assert.ok(existsSync(path), `Missing stylesheet: ${path}`)
const css = styles.map(path => readFileSync(path, "utf8")).join("\n")
const long = "CollectionTrèsLongueSansEspaces".repeat(5)
const fixtures = {
  auth: `<div class="seallo-auth"><div class="sa-split"><aside class="sa-panel"></aside><div class="sa-form-col"><div class="sa-form-wrap"><div class="sa-form-top"><a class="sa-mark">seallo</a><div class="sa-lang"><a>FR</a><a>EN</a><a>AR</a></div></div><h1>${long}</h1><input value="${long}"></div></div></div></div>`,
  navigation: `<div class="site-header"><header class="maison-nav"><div class="flex items-center gap-8"><a class="morea-lockup"><span class="morea-lockup__mark"><span class="morea-wordmark-type">MOREA</span></span></a></div><nav class="maison-nav__actions"><a class="maison-link hidden md:inline">Recherche</a><button class="maison-link md:hidden">Menu</button><a class="maison-link bag-link"><span>Panier</span><span>99</span></a><a class="maison-link">FR</a></nav></header></div>`,
  admin: `<main class="admin-page seller-page"><div class="seallo-member-grid"><article class="seallo-member"><h2>${long}</h2><div class="seallo-member__money">123456789 MAD</div></article></div><div class="admin-layout"><section class="admin-card"><div class="admin-card__body"><h1>${long}</h1><div class="admin-field-grid"><label>Nom<input class="admin-input" value="${long}"></label><label>Fichier<input type="file" class="admin-input"></label></div><div class="admin-table-wrap"><table class="admin-table"><thead><tr>${Array.from({length:8}, () => '<th>Montant confirmé</th>').join('')}</tr></thead><tbody><tr>${Array.from({length:8}, () => '<td>123 456 MAD</td>').join('')}</tr></tbody></table></div></div></section><aside class="admin-card admin-card__body">${long}</aside></div></main>`,
  checkout: `<main class="checkout"><form class="checkout-grid"><fieldset class="checkout-step"><legend>Informations de livraison</legend><div class="checkout-fields"><label class="checkout-field">Adresse<input class="checkout-input" value="${long}"></label><label class="checkout-field">Ville<select class="checkout-select"><option>${long}</option></select></label></div></fieldset><aside><ul class="checkout-lines"><li class="checkout-line"><div class="checkout-line__image" style="width:64px;height:64px"></div><div>${long}</div><strong>123 456 MAD</strong></li></ul></aside></form><div class="checkout-sticky"><div class="checkout-sticky__bar"><div>Total 123 456 MAD</div><button class="maison-button checkout-sticky__button">Confirmer ma commande maintenant</button></div></div></main>`,
  content: `<main class="store-page"><div class="store-page__body"><h1>${long}</h1><img width="1600" height="900" alt="Synthetic image"><pre>${long.repeat(3)}</pre><table><tr><td>${long.repeat(3)}</td></tr></table></div></main>`,
  platform: `<div class="platform-landing"><header class="platform-header"><div class="platform-container platform-header-inner"><a class="platform-brand">seallo</a><div class="platform-header-actions"><div class="platform-languages"><a>FR</a><a>EN</a><a>AR</a></div><a class="platform-login-nav">Connexion</a><a class="platform-button platform-header-button">Inscription</a></div></div></header><main class="platform-container"><h1>${long}</h1></main></div>`,
  document: `<div class="sc-doc"><header class="sc-header"><div class="sc-container sc-header-inner"><a class="sc-brand">Seallo</a><nav class="sc-nav"><a>Politique de confidentialité</a><a>Conditions générales d'utilisation</a></nav><div class="sc-languages"><a>FR</a><a>EN</a><a>AR</a></div></div></header><main class="sc-container sc-main"><h1>${long}</h1><pre>${long.repeat(3)}</pre></main></div>`
}
const browser = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || (existsSync("/usr/bin/chromium") ? "/usr/bin/chromium" : undefined), headless: true, args: ["--no-sandbox"] })
const sizes = [[320,640], [375,812], [768,1024], [1024,768], [1440,900], [812,375]]
const failures = []
let checks = 0
try {
  for (const [width,height] of sizes) for (const dir of ["ltr", "rtl"]) {
    const context = await browser.newContext({ viewport: {width,height}, storageState: process.env.RESPONSIVE_STORAGE_STATE || undefined })
    const page = await context.newPage()
    const routes = process.env.RESPONSIVE_URLS ? JSON.parse(readFileSync(process.env.RESPONSIVE_URLS, "utf8")) : Object.keys(fixtures)
    for (const route of routes) {
      if (process.env.RESPONSIVE_URLS) {
        const response = await page.goto(route, {waitUntil:"networkidle"})
        assert.ok(response?.ok(), `Failed route ${route}: ${response?.status()}`)
        assert.equal(new URL(page.url()).pathname, new URL(route).pathname, `Unexpected redirect: ${route}`)
        await page.locator("html").evaluate((el, direction) => el.dir = direction, dir)
      } else {
        await page.setContent(`<!doctype html><html dir="${dir}"><head><meta name="viewport" content="width=device-width, initial-scale=1"><style>${css}</style></head><body class="${route === "admin" ? "admin-body" : "storefront-body"}" data-admin-theme="seallo">${fixtures[route]}</body></html>`)
      }
      const geometry = await page.evaluate(() => {
        const viewport = document.documentElement.clientWidth
        const offenders = [...document.querySelectorAll("body *")].filter(el => {
          const r = el.getBoundingClientRect()
          if (!r.width || !r.height || getComputedStyle(el).visibility === "hidden" || getComputedStyle(el).display === "none") return false
          // Wide table/pre content is intentional only inside a local scrolling container.
          for (let parent = el.parentElement; parent && parent !== document.body; parent = parent.parentElement) {
            if (["auto","scroll"].includes(getComputedStyle(parent).overflowX) && parent.scrollWidth > parent.clientWidth) return false
          }
          return r.left < -1 || r.right > viewport + 1
        }).map(el => `${el.tagName}.${el.className}`).slice(0, 8)
        return { width: viewport, scroll: document.documentElement.scrollWidth, offenders }
      })
      checks++
      if (geometry.scroll > width + 1 || geometry.offenders.length) failures.push({route,width,height,dir,...geometry})
    }
    await context.close()
  }
} finally { await browser.close() }
mkdirSync(resolve(root,"tmp"), {recursive:true})
writeFileSync(resolve(root,"tmp/responsive-results.json"), JSON.stringify({mode:process.env.RESPONSIVE_URLS ? "live" : "component-fixtures", checks, failures},null,2))
assert.deepEqual(failures, [], JSON.stringify(failures,null,2))
console.log(`${checks} responsive geometry checks passed (${process.env.RESPONSIVE_URLS ? "live routes" : "synthetic component fixtures"}); 320–1440px, landscape, LTR/RTL`)
