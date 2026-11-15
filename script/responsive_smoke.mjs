// Browser geometry checks. See docs/responsive-validation.md for setup and live mode.
import assert from "node:assert/strict"
import { readFileSync, existsSync, mkdirSync, writeFileSync } from "node:fs"
import { resolve } from "node:path"
const { chromium } = await import(process.env.PLAYWRIGHT_MODULE || "playwright")
const root = resolve(import.meta.dirname, "..")
const cssPath = process.env.RESPONSIVE_TAILWIND || resolve(root, "app/assets/builds/tailwind.css")
assert.ok(existsSync(cssPath), "Build Tailwind first; set RESPONSIVE_TAILWIND to the compiled CSS path")
const styles = [cssPath, ...["application", "admin_pwa", "liquid_glass", "platform_home", "seallo_connect_pages", "storefront_responsive", "admin_responsive", "admin_dark", "auth_responsive"].map(name => resolve(root, `app/assets/stylesheets/${name}.css`))]
for (const path of styles) assert.ok(existsSync(path), `Missing stylesheet: ${path}`)
const css = styles.map(path => readFileSync(path, "utf8")).join("\n")
const long = "CollectionTrèsLongueSansEspaces".repeat(5)
// Render only the static picker shell; Rails helper output becomes synthetic labels.
// Classes and panel structure come from the current template, never a duplicate fixture.
const pickerTemplate = readFileSync(resolve(root, "app/views/admin/shared/_date_range_picker.html.erb"), "utf8")
const pickerShell = pickerTemplate
  .replace(/<% date_range_presets[\s\S]*?<% end %>/, '<li><a class="block rounded-lg px-3 py-1.5 text-sm">30 derniers jours</a></li>')
  .replace(/<%= local_assigns\[:size\][\s\S]*?%>/g, 'h-11 gap-2 rounded-xl px-3 text-sm')
  .replace(/<%= theme ==[\s\S]*?%>/g, 'border bg-white')
  .replace(/<%= align ==[\s\S]*?%>/g, 'md:end-0')
  .replace(/<%=[\s\S]*?%>/g, 'Choisir')
  .replace(/<%[\s\S]*?%>/g, '')
const pickerSource = readFileSync(resolve(root, "app/javascript/controllers/date_range_picker_controller.js"), "utf8")
  .replace(/^import .*$/m, 'class Controller {}')
  .replace('export default class extends Controller', 'window.RangePicker = class extends Controller')
const fixtures = {
  datePicker: `<main class="admin-page seller-page"><div class="flex justify-end p-4">${pickerShell}</div></main>`,
  accounting: `<main class="admin-page seller-page accounting-page"><section class="grid grid-cols-2 gap-2.5 lg:grid-cols-3 xl:grid-cols-5" data-cards="first">${Array.from({length:5}, (_, i) => `<div class="flex h-[110px] min-w-0 flex-col justify-between rounded-xl px-3.5 py-3" data-card="revenue${i}" data-size="regular"><div class="flex items-center justify-between gap-2"><p class="min-w-0 truncate">Valeur des commandes livrées</p><span class="whitespace-nowrap" data-change="up">+123,45 %</span></div><p class="flex items-baseline gap-x-1 text-[22px] leading-none font-bold whitespace-nowrap" data-value>123 456 789,99 <span class="text-xs">MAD</span></p><p>Comparaison avec la période précédente</p></div>`).join('')}</section><section class="max-w-[900px] rounded-xl border bg-white p-3" data-income><div class="rounded-lg px-3" data-block="goods"><div class="flex h-9 items-center justify-between gap-3 text-[13px]"><span>Coût des produits livrés</span><span data-amount="product_costs">123 456 789,99 MAD</span></div><div class="text-xs" data-product="synthetic"><div class="flex min-h-8 items-center justify-between gap-3"><span class="min-w-0 truncate">${long}</span><span class="flex shrink-0 items-baseline gap-4"><span dir="ltr">1000 × 123456,99 MAD</span><span class="w-24 text-end" data-amount="product">123456789,99</span></span></div></div></div></section></main>`,
  auth: `<div class="seallo-auth"><div class="sa-split"><aside class="sa-panel"></aside><div class="sa-form-col"><div class="sa-form-wrap"><div class="sa-form-top"><a class="sa-mark">seallo</a><div class="sa-lang"><a>FR</a><a>EN</a><a>AR</a></div></div><h1>${long}</h1><label class="fx-label">E-mail</label><input class="fx-input" type="email" value="${long}" placeholder="vous@exemple.com"><label class="fx-label">Mot de passe</label><input class="fx-input" type="password" placeholder="Votre mot de passe"></div></div></div></div>`,
  navigation: `<div class="site-header"><header class="maison-nav"><div class="flex items-center gap-8"><a class="morea-lockup"><span class="morea-lockup__mark"><span class="morea-wordmark-type">MOREA</span></span></a></div><nav class="maison-nav__actions"><a class="maison-link hidden md:inline">Recherche</a><button class="maison-link md:hidden">Menu</button><a class="maison-link bag-link"><span>Panier</span><span>99</span></a><a class="maison-link">FR</a></nav></header></div>`,
  cookies: `<div class="site-header"><header class="maison-nav"><div class="flex items-center gap-8"><a class="morea-lockup"><span class="morea-lockup__mark"><span class="morea-wordmark-type">MOREA</span></span></a></div><nav class="maison-nav__actions"><button class="maison-link md:hidden">Menu</button><a class="maison-link bag-link"><span>Panier</span><span>99</span></a></nav></header></div><main id="main-content"><h1>${long}</h1></main><div class="cookie-consent" role="dialog"><div class="cookie-consent__inner"><div class="cookie-consent__copy"><p class="cookie-consent__title">Cookies</p><p class="cookie-consent__text">${long}</p></div><div class="cookie-consent__actions"><button type="button" class="cookie-consent__button cookie-consent__button--secondary">Reject</button><button type="button" class="cookie-consent__button">Accept</button></div></div></div>`,
  admin: `<main class="admin-page seller-page"><div class="admin-page-header"><h1 class="admin-page-header__title">${long}</h1><div class="flex flex-wrap items-center gap-2"><div class="admin-page-header__actions--desktop"><button type="button" class="admin-btn">Marquer comme confirmée</button></div><button type="button" class="admin-btn-secondary">Plus d’actions</button></div></div><div class="seallo-member-grid"><article class="seallo-member"><h2>${long}</h2><div class="seallo-member__money">123456789 MAD</div></article></div><ul class="admin-mobile-list md:hidden"><li><a class="admin-mobile-list__item" href="#"><div class="admin-mobile-list__top"><div class="min-w-0"><span class="admin-mobile-list__title">#1042</span><p class="admin-mobile-list__name">${long}</p><p class="admin-mobile-list__meta">Casablanca, 0612345678</p></div><span class="admin-badge">Nouveau</span></div><p class="admin-mobile-list__amount">1 234 MAD</p></a></li><li class="admin-mobile-list__card"><div class="admin-mobile-list__top"><span class="admin-mobile-list__title">#1043</span><p class="admin-mobile-list__amount">890 MAD</p></div><div class="admin-mobile-list__actions"><button type="button" class="admin-btn">Réclamer</button><button type="button" class="admin-btn-secondary">Appeler</button></div></li></ul><div class="admin-layout"><section class="admin-card"><div class="admin-card__body"><h1>${long}</h1><div class="admin-field-grid"><label>Nom<input class="admin-input" value="${long}"></label><label>Fichier<input type="file" class="admin-input"></label></div><ul><li class="admin-order-line-item flex items-center gap-3"><div class="min-w-0 flex-1"><p class="whitespace-normal break-words font-medium">${long}</p></div><div class="admin-order-line-item__totals flex items-center gap-3"><span>123 MAD × 2</span><span class="w-24 text-end">246 MAD</span></div></li></ul><div class="admin-table-wrap"><table class="admin-table"><thead><tr>${Array.from({length:8}, () => '<th>Montant confirmé</th>').join('')}</tr></thead><tbody><tr>${Array.from({length:8}, () => '<td>123 456 MAD</td>').join('')}</tr></tbody></table></div></div></section><aside class="admin-card admin-card__body">${long}</aside></div><div class="space-y-3" data-orders-page>
  <header class="flex flex-col gap-3 rounded-3xl bg-[#1c1c1e] px-4 py-3 text-white" data-orders-header>
    <div class="flex min-w-0 items-center gap-3"><h1 class="text-xl font-bold">Order management</h1></div>
    <div class="flex min-w-0 flex-wrap items-center gap-2" data-orders-header-actions>
      <button type="button" class="inline-flex min-h-10 items-center rounded-full bg-white px-3.5 text-[13px] font-semibold text-[#1c1c1e]">+ New order</button>
      <button type="button" class="inline-flex min-h-10 items-center rounded-full bg-white/10 px-3.5 text-[13px] font-semibold text-white">Ship</button>
    </div>
  </header>
  <section id="orders-list" class="rounded-3xl border border-[#e0e0e5] bg-white p-3" data-orders-list>
    <form class="mt-3 space-y-2" data-orders-filters>
      <input class="admin-orders-filter h-10 w-full min-w-0 rounded-full border border-[#e0e0e5] bg-white px-3 text-base" value="${long}" />
      <div class="grid grid-cols-1 gap-2 sm:grid-cols-2 md:flex md:flex-wrap" data-orders-filter-row>
        <select class="admin-orders-filter h-10 w-full min-w-0 rounded-full border border-[#e0e0e5] bg-white px-3 text-base"><option>${long}</option></select>
        <select class="admin-orders-filter h-10 w-full min-w-0 rounded-full border border-[#e0e0e5] bg-white px-3 text-base"><option>All products</option></select>
      </div>
    </form>
    <ul class="admin-mobile-list mt-3 overflow-hidden rounded-2xl border border-[#e0e0e5] md:hidden" data-orders-mobile-list>
      <li class="admin-mobile-list__card">
        <div class="admin-mobile-list__top"><div class="min-w-0"><span class="admin-mobile-list__title">#1042</span><p class="admin-mobile-list__name">${long}</p><p class="admin-mobile-list__meta">Casablanca · 0612345678</p></div><p class="admin-mobile-list__amount">1 234 MAD</p></div>
        <div class="admin-mobile-list__badges"><span class="admin-badge">Pending</span><span class="admin-badge">Not shipped</span></div>
        <div class="admin-mobile-list__actions"><button type="button" class="admin-btn">View</button><button type="button" class="admin-btn-secondary">Edit</button><button type="button" class="admin-btn-secondary">Duplicate</button></div>
      </li>
    </ul>
    <div class="mt-3 hidden overflow-x-auto rounded-2xl border border-[#e0e0e5] md:block" data-orders-table-wrap>
      <table class="w-full text-left text-[13px]" data-orders-table><thead><tr>${Array.from({length:11}, () => '<th class="px-3 py-2.5 whitespace-nowrap">Column</th>').join('')}</tr></thead><tbody><tr>${Array.from({length:11}, () => '<td class="px-3 py-2.5">Value</td>').join('')}</tr></tbody></table>
    </div>
  </section>
</div>
<div class="admin-mobile-actions"><button type="button" class="admin-btn">Marquer comme confirmée</button></div></main>`,
  callPanel: `<div data-seller-shell><div data-order-modal>
  <div data-order-modal-panel data-call-panel role="dialog" aria-modal="true" aria-labelledby="call-panel-title">
    <header class="call-panel-header flex items-start justify-between gap-3 px-6 pt-5">
      <div class="call-panel-header__copy min-w-0">
        <h2 id="call-panel-title" class="call-panel-header__title flex flex-wrap items-center gap-x-2 gap-y-1 text-2xl font-bold text-[#1c1c1e]">
          <span>Appel <span class="text-[#6e6e73]" dir="ltr">#CMD-1042</span></span>
        </h2>
        <p class="call-panel-header__subtitle mt-1 text-sm text-[#6e6e73]">Parlez au client, vérifiez la commande, puis choisissez le résultat de l’appel.</p>
      </div>
      <div class="call-panel-header__tools flex shrink-0 items-center gap-2">
        <span class="call-panel-timer inline-flex items-center gap-2 rounded-full bg-[#1c1c1e] px-3.5 py-1.5 text-sm font-semibold text-white tabular-nums"><span dir="ltr">00:42</span></span>
        <button type="button" class="call-panel-close grid size-8 shrink-0 place-items-center rounded-full bg-[#e5484d] text-white" aria-label="Fermer">×</button>
      </div>
    </header>
    <div class="call-panel-body px-6 pt-3 pb-5">
      <form class="space-y-3">
        <div class="grid items-start gap-x-6 gap-y-3 lg:grid-cols-2">
          <section class="space-y-2" data-section="customer">
            <h3 class="text-[13px] font-semibold">Informations client</h3>
            <div class="grid gap-x-3 gap-y-2 sm:grid-cols-2">
              <div class="min-w-0"><label class="admin-label">Nom du client</label><input class="admin-input !rounded-xl" value="${long}"></div>
              <div class="min-w-0"><label class="admin-label">Téléphone</label>
                <div class="call-panel-phone flex min-w-0 items-center gap-1.5">
                  <input class="admin-input !rounded-xl min-w-0 flex-1" type="tel" value="0612345678" dir="ltr">
                  <a class="grid size-9 shrink-0 place-items-center rounded-full bg-[#e3f3e8]" href="tel:0612345678">☎</a>
                  <button type="button" class="grid size-9 shrink-0 place-items-center rounded-full bg-[#ececf0]">⎘</button>
                </div>
              </div>
              <div class="min-w-0"><label class="admin-label">Deuxième téléphone</label><input class="admin-input !rounded-xl" type="tel" value="" dir="ltr"></div>
              <div class="min-w-0"><label class="admin-label">Ville</label><input class="admin-input !rounded-xl" value="Casablanca"></div>
            </div>
            <div class="min-w-0"><label class="admin-label">Adresse</label><input class="admin-input !rounded-xl" value="${long}"></div>
            <div class="min-w-0"><label class="admin-label">Notes de l’appel</label><textarea class="admin-input !rounded-xl" rows="2" placeholder="Raison d’annulation…"></textarea></div>
          </section>
          <section class="space-y-2" data-section="items">
            <h3 class="text-[13px] font-semibold">Produits</h3>
            <ul class="divide-y divide-[#1c1c1e]/10 rounded-xl border border-[#1c1c1e]/10 bg-white/50">
              <li class="call-panel-line space-y-1.5 px-3 py-2.5">
                <div class="flex items-start justify-between gap-2">
                  <p class="min-w-0 flex-1 break-words text-[13px] font-semibold" dir="auto">${long}</p>
                  <button type="button" class="admin-btn-plain admin-btn-plain--critical shrink-0">Retirer</button>
                </div>
                <div class="call-panel-line__controls grid grid-cols-[minmax(0,1fr)_5rem_auto] items-end gap-2">
                  <div class="min-w-0"><span class="admin-label">Variante</span><select class="admin-input !rounded-xl"><option>${long}</option></select></div>
                  <div class="min-w-0"><span class="admin-label">Quantité</span><input class="admin-input !rounded-xl text-center" type="number" value="2"></div>
                  <p class="call-panel-line__total pb-2 text-end text-[13px] font-semibold tabular-nums" dir="ltr">1 234 MAD</p>
                </div>
              </li>
            </ul>
          </section>
        </div>
        <section class="call-panel-result border-t border-[#1c1c1e]/10 pt-3" data-section="result">
          <h3 class="mb-2 text-[13px] font-semibold">Résultat de l’appel</h3>
          <div class="call-panel-actions flex flex-wrap items-center gap-2">
            <button type="button" class="inline-flex h-9 items-center justify-center rounded-full bg-[#2f9d5c] px-4 text-[13px] font-semibold text-white">Confirmer</button>
            <button type="button" class="inline-flex h-9 items-center justify-center rounded-full bg-[#e5484d] px-4 text-[13px] font-semibold text-white">Annuler la commande</button>
            <button type="button" class="inline-flex h-9 items-center justify-center rounded-full bg-[#fdf0d9] px-4 text-[13px] font-semibold text-[#b4730f]">Injoignable</button>
            <button type="button" class="inline-flex h-9 items-center justify-center rounded-full bg-[#e6f0fd] px-4 text-[13px] font-semibold text-[#2f6fed]">Rappeler plus tard</button>
            <button type="button" class="inline-flex h-9 items-center justify-center rounded-full bg-[#ececf0] px-4 text-[13px] font-semibold">Faux numéro</button>
            <button type="button" class="admin-btn-secondary call-panel-hang-up ms-auto">Raccrocher sans résultat</button>
          </div>
        </section>
      </form>
    </div>
  </div>
</div></div>`,
  checkout: `<main class="checkout"><form class="checkout-grid"><fieldset class="checkout-step"><legend>Informations de livraison</legend><div class="checkout-fields"><label class="checkout-field">Adresse<input class="checkout-input" value="${long}"></label><label class="checkout-field">Ville<select class="checkout-select"><option>${long}</option></select></label></div></fieldset><aside><ul class="checkout-lines"><li class="checkout-line"><div class="checkout-line__image" style="width:64px;height:64px"></div><div>${long}</div><strong>123 456 MAD</strong></li></ul></aside></form><div class="checkout-sticky"><div class="checkout-sticky__bar"><div>Total 123 456 MAD</div><button class="maison-button checkout-sticky__button">Confirmer ma commande maintenant</button></div></div></main>`,
  content: `<main class="store-page"><div class="store-page__body"><h1>${long}</h1><img width="1600" height="900" alt="Synthetic image"><pre>${long.repeat(3)}</pre><table><tr><td>${long.repeat(3)}</td></tr></table></div></main>`,
  platform: `<div class="platform-landing"><header class="platform-header"><div class="platform-container platform-header-inner"><a class="platform-brand">seallo</a><div class="platform-header-actions"><div class="platform-languages"><a>FR</a><a>EN</a><a>AR</a></div><a class="platform-login-nav">Connexion</a><a class="platform-button platform-header-button">Inscription</a></div></div></header><main class="platform-container"><h1>${long}</h1></main></div>`,
  document: `<div class="sc-doc"><header class="sc-header"><div class="sc-container sc-header-inner"><a class="sc-brand"><img class="sc-logo" width="640" height="160" alt="" src="data:image/svg+xml,${encodeURIComponent('<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"640\" height=\"160\"><rect width=\"640\" height=\"160\" fill=\"#1c1b19\"/><text x=\"24\" y=\"100\" fill=\"#fff\" font-size=\"72\" font-family=\"sans-serif\">SealloCRM</text></svg>')}"><span class="sc-brand__name">Seallo Connect</span></a><nav class="sc-nav"><a>Overview and support</a><a>Pricing</a><a>Privacy policy</a><a>Terms of service</a><a>Cookie policy</a><a>Refunds</a><a>Your data rights</a></nav><div class="sc-languages"><a>FR</a><a>EN</a><a>AR</a></div></div></header><main class="sc-container sc-main"><h1>${long}</h1><pre>${long.repeat(3)}</pre></main></div>`
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
        const bodyClass = ["admin", "accounting", "datePicker", "callPanel"].includes(route)
          ? "admin-body"
          : route === "cookies" ? "storefront-body has-cookie-notice" : "storefront-body"
        await page.setContent(`<!doctype html><html dir="${dir}"><head><meta name="viewport" content="width=device-width, initial-scale=1"><style>${css}</style></head><body class="${bodyClass}" data-admin-theme="seallo">${["admin", "accounting", "datePicker", "callPanel"].includes(route) ? `<div class="flex"><div class="min-w-0 flex-1">${fixtures[route]}</div></div>` : fixtures[route]}</body></html>`)
      }
      if (!process.env.RESPONSIVE_URLS && route === "datePicker") {
        await page.addScriptTag({content: pickerSource})
        await page.evaluate(() => {
          const picker = new window.RangePicker()
          picker.element = document.querySelector('[data-controller="date-range-picker"]')
          for (const target of ["panel", "button", "calendar", "startField", "endField", "count", "apply", "months", "customToggle"]) picker[`${target}Target`] = picker.element.querySelector(`[data-date-range-picker-target="${target}"]`)
          picker.configValue = {today:"2026-11-05",from:"2026-10-06",to:"2026-11-05",rtl:document.documentElement.dir === "rtl",months:Array.from({length:12}, (_, i) => `Mois ${i+1}`),monthsShort:Array.from({length:12}, (_,i) => `M${i+1}`),weekdays:["Lu","Ma","Me","Je","Ve","Sa","Di"],labels:{previous:"Précédent",next:"Suivant",pickEnd:"Choisir la fin",daysOne:"1 jour",daysOther:"%{count} jours"}}
          picker.connect(); picker.open(); picker.showCustom()
        })
        assert.ok(await page.locator('button[data-date]').count() >= 28, "Real date controller renders calendar days")
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
      if (!process.env.RESPONSIVE_URLS && route === "cookies") {
        const banner = await page.locator(".cookie-consent").boundingBox()
        assert.ok(banner, "storefront cookie banner should render")
        assert.ok(Math.abs((banner.y + banner.height) - height) <= 2, `storefront cookie banner must sit on the bottom edge (got y=${banner.y}, h=${banner.height}, viewport=${height})`)
        assert.ok(banner.y > height * 0.4, "storefront cookie banner must not sit in the top half")
        checks++
      }
      if (!process.env.RESPONSIVE_URLS && width <= 767 && ["auth", "admin", "checkout", "callPanel"].includes(route)) {
        const fontSizes = await page.locator('input:not([type="checkbox"]):not([type="radio"]):not([type="file"]), select, textarea').evaluateAll(els =>
          els.map(el => ({ tag: el.tagName, className: el.className, size: parseFloat(getComputedStyle(el).fontSize) }))
        )
        assert.ok(fontSizes.length, `${route} text inputs should render`)
        const tooSmall = fontSizes.filter(entry => entry.size < 16)
        assert.equal(tooSmall.length, 0, `${route} inputs must be ≥16px to avoid iOS focus zoom (got ${JSON.stringify(tooSmall)})`)
        checks++
      }
    }
    await context.close()
  }
} finally { await browser.close() }
mkdirSync(resolve(root,"tmp"), {recursive:true})
writeFileSync(resolve(root,"tmp/responsive-results.json"), JSON.stringify({mode:process.env.RESPONSIVE_URLS ? "live" : "component-fixtures", checks, failures},null,2))
assert.deepEqual(failures, [], JSON.stringify(failures,null,2))
console.log(`${checks} responsive geometry checks passed (${process.env.RESPONSIVE_URLS ? "live routes" : "synthetic component fixtures"}); 320–1440px, landscape, LTR/RTL`)
