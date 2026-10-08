// Offline cache for the app shell. The ROM and calculator memory live in
// IndexedDB, not here. Bump VERSION when shipping new files.
const VERSION = 'ti84ce-d107fb4';
const SHELL = [
  './', 'index.html', 'style.css', 'app.js', 'runner.js', 'worker.js', 'storage.js',
  'core/cpu.js', 'core/devices.js', 'core/emulator.js', 'core/lcd.js', 'core/memory.js', 'core/scheduler.js',
  'manifest.webmanifest', 'icons/icon-180.png', 'icons/icon-192.png', 'icons/icon-512.png',
];

self.addEventListener('install', (e) => {
  e.waitUntil(caches.open(VERSION).then((c) => c.addAll(SHELL)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', (e) => {
  e.waitUntil(caches.keys()
    .then((keys) => Promise.all(keys.filter((k) => k !== VERSION).map((k) => caches.delete(k))))
    .then(() => self.clients.claim()));
});

// Network first so updates arrive when online; cache when offline.
self.addEventListener('fetch', (e) => {
  if (e.request.method !== 'GET') return;
  e.respondWith(fetch(e.request).then((res) => {
    if (res.ok && new URL(e.request.url).origin === location.origin) {
      const copy = res.clone();
      caches.open(VERSION).then((c) => c.put(e.request, copy));
    }
    return res;
  }).catch(() => caches.match(e.request, { ignoreSearch: true })));
});
