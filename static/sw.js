// CleanHabit service worker — light redesign.
// HTML/navigations are ALWAYS fetched fresh (no stale app shell); other GET
// assets use network-first with a cache fallback for offline.
const CACHE = 'cleanhouse-v5-light';

self.addEventListener('install', () => {
  self.skipWaiting();
});

self.addEventListener('activate', e => {
  // Purge every old cache so the previous (old-design) shell can't be served.
  e.waitUntil(
    caches.keys()
      .then(keys => Promise.all(keys.map(k => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', e => {
  if (e.request.method !== 'GET') return;
  if (e.request.url.includes('/api/')) return; // API: let it hit network directly

  const isHTML =
    e.request.mode === 'navigate' || e.request.destination === 'document';

  if (isHTML) {
    // Always bypass the HTTP cache for the document — guarantees fresh design.
    e.respondWith(
      fetch(e.request, { cache: 'reload' }).catch(() => caches.match(e.request))
    );
    return;
  }

  // Static assets: network-first, fall back to cache when offline.
  e.respondWith(
    fetch(e.request)
      .then(res => {
        const clone = res.clone();
        caches.open(CACHE).then(c => c.put(e.request, clone));
        return res;
      })
      .catch(() => caches.match(e.request))
  );
});
