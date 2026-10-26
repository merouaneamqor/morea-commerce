// Admin stays online-only. Never cache authenticated pages, API data or writes.
self.addEventListener("install", () => self.skipWaiting())
self.addEventListener("activate", (event) => event.waitUntil(self.clients.claim()))

self.addEventListener("fetch", (event) => {
  const url = new URL(event.request.url)
  const adminPath = url.pathname === "/admin" || url.pathname.startsWith("/admin/")
  if (event.request.method !== "GET" || event.request.mode !== "navigate" ||
      url.origin !== self.location.origin || !adminPath) return

  event.respondWith(fetch(event.request).catch(() => new Response(`<!doctype html>
<html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Seallo crm — Offline</title>
<style>body{font:18px system-ui;margin:15vh auto;padding:24px;max-width:36rem;line-height:1.6}a{color:#2e4dd5}</style>
<h1>Connection required</h1><p>Reconnect to use your workspace.</p>
<p lang="fr">Connexion requise pour utiliser votre espace.</p>
<p lang="ar" dir="rtl">يلزم الاتصال بالإنترنت لاستخدام مساحة العمل.</p>
<a href="/admin">Retry / Réessayer / إعادة المحاولة</a></html>`, {
    status: 503,
    headers: { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-store" }
  })))
})

// Order alerts: show a system notification, and tell any open admin tab so it can play the chime.
self.addEventListener("push", (event) => {
  let data = {}
  try { data = event.data ? event.data.json() : {} } catch (_) { data = { title: "Seallo", body: event.data ? event.data.text() : "" } }
  const show = self.registration.showNotification(data.title || "Seallo", {
    body: data.body || "",
    tag: data.tag,
    renotify: Boolean(data.tag),
    icon: "/icon-128.png",
    badge: "/icon-48.png",
    requireInteraction: true,
    data: { url: data.url || "/admin/confirmations" }
  })
  const notify = self.clients.matchAll({ type: "window", includeUncontrolled: true })
    .then((clients) => clients.forEach((client) => client.postMessage({ kind: data.kind || "notification", ...data })))
  event.waitUntil(Promise.all([show, notify]))
})

self.addEventListener("notificationclick", (event) => {
  event.notification.close()
  const url = new URL(event.notification.data?.url || "/admin/confirmations", self.location.origin).href
  event.waitUntil(self.clients.matchAll({ type: "window", includeUncontrolled: true }).then((clients) => {
    const open = clients.find((client) => client.url.startsWith(`${self.location.origin}/admin`))
    return open ? open.focus() : self.clients.openWindow(url)
  }))
})
