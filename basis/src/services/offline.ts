// Registers the service worker that precaches the app shell (generated at build
// time by the `basis-sw` Vite plugin) so Basis opens offline.

export function registerServiceWorker() {
  if (!import.meta.env.PROD || !('serviceWorker' in navigator)) return
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('./sw.js').catch((e) => console.warn('Basis: service worker registration failed', e))
  })
}
