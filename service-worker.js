// نسخة المسجّل — تُبدَّل عند كل تحديث لضمان تنشيط SW جديد
const SW_VERSION = 'v4-2026-07-13-a';
const STATIC_CACHE = 'sg-static-' + SW_VERSION;

self.addEventListener('install', () => self.skipWaiting());

self.addEventListener('activate', (e) => {
  e.waitUntil((async () => {
    // احذف كل الكاشات القديمة
    const keys = await caches.keys();
    await Promise.all(keys.filter(k => k !== STATIC_CACHE).map(k => caches.delete(k)));
    await self.clients.claim();
    // بلّغ كل الصفحات المفتوحة إن السيرفس ووركر تحدّث — عشان تعيد التحميل
    const clients = await self.clients.matchAll({ type: 'window' });
    for (const client of clients) {
      try { client.postMessage({ type: 'sw-updated' }); } catch (e) {}
    }
  })());
});

self.addEventListener('fetch', (e) => {
  if (e.request.method !== 'GET') return;
  const url = new URL(e.request.url);

  // Supabase وأي API: مباشرة من الشبكة
  if (url.href.includes('supabase.co')) return;

  const sameOrigin = url.origin === self.location.origin;
  const isHtml = url.pathname.endsWith('.html') || url.pathname === '/' || url.pathname.endsWith('/');
  const isJs = url.pathname.endsWith('.js') && sameOrigin;
  const isJson = url.pathname.endsWith('.json') && sameOrigin;

  // HTML و JS/JSON محلي: دايمًا من الشبكة (بلا كاش) عشان يوصل التحديث فورًا
  if (isHtml || isJs || isJson) {
    e.respondWith(fetch(e.request, { cache: 'no-store' }).catch(() => caches.match(e.request)));
    return;
  }

  // خطوط وصور و CDN: cache-first (يندر تغييرها)
  e.respondWith((async () => {
    const cached = await caches.match(e.request);
    if (cached) return cached;
    try {
      const res = await fetch(e.request);
      if (res && res.ok && (sameOrigin || url.hostname.includes('fonts.') || url.hostname.includes('cdn.') || url.hostname.includes('unpkg.') || url.hostname.includes('jsdelivr.'))) {
        const cache = await caches.open(STATIC_CACHE);
        cache.put(e.request, res.clone()).catch(() => {});
      }
      return res;
    } catch (err) {
      return caches.match(e.request);
    }
  })());
});
