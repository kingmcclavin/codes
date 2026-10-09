// Offline support: cache the app shell; network first so updates arrive.
const CACHE = 'basis-v33';
const SHELL = [
  './', 'index.html', 'styles.css', 'manifest.webmanifest', 'icons/favicon.png', 'icons/wordmark.png', 'icons/icon-192.png',
  'js/app.js', 'js/util.js', 'js/model.js', 'js/store.js', 'js/elements.js', 'js/render.js', 'js/recognizer.js',
  'js/erase.js', 'js/scribble.js', 'js/goodnotes.js', 'js/basisfile.js', 'js/notability.js', 'js/history.js', 'js/canvas.js', 'js/editor.js', 'js/library.js', 'js/calculator.js', 'js/ui.js',
  'js/icons.js', 'js/version.js', 'js/libicons.js', 'js/features.js', 'js/tour.js', 'js/ai.js', 'js/aiscreen.js', 'js/recognize.js', 'js/sync.js', 'js/syncsettings.js', 'js/pdf.js', 'js/calc/engine.js', 'js/calc/units.js', 'js/calc/formulas.js', 'js/calc/store.js',
  'vendor/pdf.min.js', 'vendor/pdf.worker.min.js', 'vendor/jspdf.umd.min.js', 'vendor/anthropic-sdk.mjs',
];

self.addEventListener('install', (e) => {
  e.waitUntil(caches.open(CACHE).then((c) => c.addAll(SHELL)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', (e) => {
  e.waitUntil(caches.keys().then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)))).then(() => self.clients.claim()));
});

self.addEventListener('fetch', (e) => {
  if (e.request.method !== 'GET') return;
  if (new URL(e.request.url).pathname.includes('/api/')) return; // sign-in service: never cache
  e.respondWith(
    fetch(e.request)
      .then((res) => {
        if (res.ok && (new URL(e.request.url).origin === location.origin || e.request.url.includes('cdnjs') || e.request.url.includes('fonts.g'))) {
          const copy = res.clone();
          caches.open(CACHE).then((c) => c.put(e.request, copy));
        }
        return res;
      })
      .catch(() => caches.match(e.request).then((r) => r || caches.match('index.html'))),
  );
});
