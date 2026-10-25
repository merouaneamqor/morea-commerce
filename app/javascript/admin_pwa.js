const DISMISS_KEY = "seallo.admin.install.dismissedAt"
const COOLDOWN = 7 * 24 * 60 * 60 * 1000

export function isIosDevice(navigator) {
  return /iPad|iPhone|iPod/.test(navigator.userAgent || "") ||
    (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1)
}

export function setupAdminPwa({ window, document, navigator, storage, now = Date.now }) {
  let deferredPrompt = null
  let installed = false
  let dismissedAt = 0
  let registrationStarted = false
  const banner = () => document.querySelector("[data-admin-pwa]")
  const adminPath = () => window.location.pathname === "/admin" || window.location.pathname.startsWith("/admin/")
  const standalone = () => installed || navigator.standalone === true ||
    window.matchMedia?.("(display-mode: standalone)").matches

  function coolingDown() {
    try {
      const saved = Number(storage()?.getItem(DISMISS_KEY))
      if (Number.isFinite(saved) && saved > dismissedAt) dismissedAt = saved
    } catch (_) { /* Storage may be blocked in private browsing. */ }
    return dismissedAt > 0 && now() - dismissedAt < COOLDOWN
  }

  function hide() {
    const element = banner()
    if (element) {
      element.hidden = true
      element.querySelector("[data-admin-pwa-instructions]").hidden = true
      element.querySelector("[data-admin-pwa-install]").setAttribute("aria-expanded", "false")
    }
  }

  function dismiss() {
    dismissedAt = now()
    try { storage()?.setItem(DISMISS_KEY, String(dismissedAt)) } catch (_) { /* Keep the in-memory cooldown. */ }
    hide()
  }

  function refresh() {
    const element = banner()
    if (!element || !adminPath()) return
    if (!registrationStarted && window.isSecureContext && navigator.serviceWorker) {
      registrationStarted = true
      navigator.serviceWorker.register("/admin/service-worker.js", { scope: "/admin" }).catch(() => {})
    }
    if (standalone() || coolingDown()) return hide()
    element.querySelector("[data-admin-pwa-ios]").hidden = !isIosDevice(navigator)
    element.querySelector("[data-admin-pwa-other]").hidden = isIosDevice(navigator)
    element.hidden = false
  }

  async function install(element) {
    if (deferredPrompt) {
      const prompt = deferredPrompt
      deferredPrompt = null
      try {
        // Called directly from the user's click; never open a native prompt on load.
        await prompt.prompt()
        const choice = await prompt.userChoice
        if (choice?.outcome === "accepted") {
          installed = true
          hide()
        } else {
          dismiss()
        }
        return
      } catch (_) { /* Offer browser instructions if native installation fails. */ }
    }
    const instructions = element.querySelector("[data-admin-pwa-instructions]")
    instructions.hidden = !instructions.hidden
    element.querySelector("[data-admin-pwa-install]").setAttribute("aria-expanded", String(!instructions.hidden))
  }

  window.addEventListener("beforeinstallprompt", (event) => {
    if (!adminPath()) return
    event.preventDefault()
    deferredPrompt = event
    refresh()
  })
  window.addEventListener("appinstalled", () => {
    installed = true
    deferredPrompt = null
    hide()
  })
  document.addEventListener("click", (event) => {
    const element = event.target.closest?.("[data-admin-pwa]")
    if (!element) return
    if (event.target.closest("[data-admin-pwa-dismiss]")) dismiss()
    if (event.target.closest("[data-admin-pwa-install]")) void install(element)
  })
  document.addEventListener("turbo:load", refresh)
  document.addEventListener("DOMContentLoaded", refresh)
  // Do not restore a previously opened prompt from Turbo's page cache.
  document.addEventListener("turbo:before-cache", hide)
  if (document.readyState !== "loading") refresh()
}

if (typeof window !== "undefined" && !window.__sealloAdminPwa) {
  window.__sealloAdminPwa = true
  setupAdminPwa({ window, document, navigator, storage: () => window.localStorage })
}
