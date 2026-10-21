// Cache everything once so the app keeps working offline / when the tunnel URL dies.
const CACHE = 'navi-fast-v6';
const FILES = ['/fast/', '/fast/app.js', '/fast/app.css', '/fast/manifest.webmanifest',
  '/fast/icon-192.png', '/fast/icon-512.png', '/fast/ort.wasm.min.mjs',
  '/fast/ort-wasm-simd-threaded.mjs', '/fast/ort-wasm-simd-threaded.wasm', '/fast/model.onnx', '/fast/depth.onnx'];

self.addEventListener('install', (e) => {
  e.waitUntil(caches.open(CACHE).then((c) => c.addAll(FILES)).then(() => self.skipWaiting()));
});
self.addEventListener('activate', (e) => {
  e.waitUntil(caches.keys().then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
    .then(() => self.clients.claim()));
});
// Big binaries: cache first. Page/code: network first so updates land, cache when offline.
const HEAVY = /\.(onnx|wasm|mjs|png)$/;
self.addEventListener('fetch', (e) => {
  const url = new URL(e.request.url);
  if (e.request.method !== 'GET' || !url.pathname.startsWith('/fast')) return;
  const key = url.pathname === '/fast' || url.pathname === '/fast/index.html' ? '/fast/' : url.pathname;
  if (HEAVY.test(key)) {
    e.respondWith(caches.match(key).then((hit) => hit || fetch(e.request)));
    return;
  }
  e.respondWith(fetch(e.request).then((res) => {
    if (res.ok) { const copy = res.clone(); caches.open(CACHE).then((c) => c.put(key, copy)); }
    return res;
  }).catch(() => caches.match(key)));
});
