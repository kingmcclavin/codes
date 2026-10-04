import react from '@vitejs/plugin-react'
import { defineConfig, type Plugin } from 'vite'

/**
 * Generates `sw.js` at build time with a precache list of every emitted asset,
 * so Basis works fully offline after the first visit.
 */
function basisServiceWorker(): Plugin {
  return {
    name: 'basis-sw',
    apply: 'build',
    generateBundle(_options, bundle) {
      // Browsers only fetch woff2 for our fonts, so skip the .ttf/.woff fallbacks.
      const files = Object.keys(bundle).filter((f) => !/\.(map|ttf|woff)$/.test(f))
      const version = Date.now().toString(36)
      const precache = ['./', ...files.map((f) => `./${f}`), './favicon.svg', './manifest.webmanifest', './icons/icon-192.png', './icons/apple-touch-icon.png']
      const source = `// Basis service worker (generated)
const CACHE = 'basis-${version}'
const PRECACHE = ${JSON.stringify(precache)}

self.addEventListener('install', (e) => {
  e.waitUntil(caches.open(CACHE).then((c) => c.addAll(PRECACHE)).then(() => self.skipWaiting()))
})

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys().then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)))).then(() => self.clients.claim()),
  )
})

self.addEventListener('fetch', (e) => {
  const req = e.request
  if (req.method !== 'GET' || new URL(req.url).origin !== location.origin) return
  if (req.mode === 'navigate') {
    // Network first for the page so deploys show up; cached shell when offline.
    e.respondWith(fetch(req).then((res) => { const copy = res.clone(); caches.open(CACHE).then((c) => c.put('./', copy)); return res }).catch(() => caches.match('./')))
    return
  }
  e.respondWith(caches.match(req).then((hit) => hit || fetch(req).then((res) => { if (res.ok) { const copy = res.clone(); caches.open(CACHE).then((c) => c.put(req, copy)) } return res })))
})
`
      this.emitFile({ type: 'asset', fileName: 'sw.js', source })
    },
  }
}

// `base: './'` keeps every asset path relative, so the same build works at a
// domain root (Vercel/Netlify) or a sub-path (GitHub Pages: /<repo>/).
export default defineConfig({
  base: './',
  plugins: [react(), basisServiceWorker()],
  build: {
    chunkSizeWarningLimit: 1600,
  },
})
