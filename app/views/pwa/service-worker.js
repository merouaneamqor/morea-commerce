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
