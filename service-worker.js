const CACHE = 'sg-cache-v1';
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (e) => e.waitUntil(
  caches.keys().then(keys => Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)))).then(() => self.clients.claim())
));
self.addEventListener('fetch', (e) => {
  if (e.request.method !== 'GET') return;
  // لا نتدخل في طلبات الـ API (Supabase) — دايمًا من الشبكة
  if (e.request.url.includes('supabase.co')) return;
  e.respondWith(
    fetch(e.request)
      .then((res) => {
        if (res && res.ok && (e.request.url.startsWith(self.location.origin) || e.request.url.includes('fonts.') || e.request.url.includes('cdn.'))) {
          const copy = res.clone();
          caches.open(CACHE).then(c => c.put(e.request, copy)).catch(() => {});
        }
        return res;
      })
      .catch(() => caches.match(e.request))
  );
});
