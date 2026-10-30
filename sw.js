// Mis Cuentas Claras — funciona sin internet.
// Al cambiar archivos de la app, sube el número de versión (cuentas-v4, v5…).
const VERSION = "cuentas-v4";
const CORE = ["./", "./index.html", "./supabase.js", "./config.js", "./manifest.webmanifest",
  "./icon-192.png", "./icon-512.png", "./apple-touch-icon.png"];

self.addEventListener("install", e => {
  e.waitUntil(caches.open(VERSION).then(c => c.addAll(CORE)).then(() => self.skipWaiting()));
});
self.addEventListener("activate", e => {
  e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k !== VERSION).map(k => caches.delete(k)))).then(() => self.clients.claim()));
});
self.addEventListener("fetch", e => {
  const req = e.request;
  if (req.method !== "GET") return;
  const url = new URL(req.url);
  // Archivos de la app: primero internet (para recibir mejoras); sin internet, la copia guardada.
  if (url.origin === location.origin) {
    e.respondWith(fetch(req).then(r => {
      if (r.ok) { const cp = r.clone(); caches.open(VERSION).then(c => c.put(req.mode === "navigate" ? "./index.html" : req, cp)); }
      return r;
    }).catch(() => caches.match(req.mode === "navigate" ? "./index.html" : req, { ignoreSearch: true })));
    return;
  }
  // Tipografías: copia guardada primero.
  if (url.hostname === "fonts.googleapis.com" || url.hostname === "fonts.gstatic.com") {
    e.respondWith(caches.match(req).then(hit => hit || fetch(req).then(r => {
      const cp = r.clone(); caches.open(VERSION).then(c => c.put(req, cp)); return r;
    })));
  }
  // Todo lo demás (Supabase: tus datos y tu sesión) va directo a internet, nunca se guarda en caché.
});
