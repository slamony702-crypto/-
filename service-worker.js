// نسخة المسجّل — تُبدَّل عند كل تحديث لضمان تنشيط SW جديد
const SW_VERSION = 'v33-2026-07-14-brand-colors';
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

// عند الضغط على الإشعار: يفتح التطبيق ويوجّه للرابط المطلوب
self.addEventListener('notificationclick', (e) => {
  e.notification.close();
  const targetUrl = (e.notification.data && e.notification.data.url) || '';
  e.waitUntil((async () => {
    const clients = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    // لو التطبيق مفتوح: ركّز عليه وحدّث الـ hash
    for (const client of clients) {
      if (client.url.includes(self.location.origin)) {
        try { client.focus(); } catch (e) {}
        if (targetUrl) {
          try { client.postMessage({ type: 'navigate', url: targetUrl }); } catch (e) {}
        }
        return;
      }
    }
    // مش مفتوح: افتح نافذة جديدة
    if (self.clients.openWindow) {
      const openUrl = targetUrl ? self.location.origin + '/' + (targetUrl.startsWith('#') ? targetUrl : '#' + targetUrl) : self.location.origin;
      await self.clients.openWindow(openUrl);
    }
  })());
});

self.addEventListener('fetch', (e) => {
  if (e.request.method !== 'GET') return;
  const url = new URL(e.request.url);

  // Supabase وأي API: مباشرة من الشبكة
  if (url.href.includes('supabase.co')) return;
  // API endpoints المحلية: بلا كاش
  if (url.pathname.startsWith('/api/')) return;

  const sameOrigin = url.origin === self.location.origin;
  const isHtml = url.pathname.endsWith('.html') || url.pathname === '/' || url.pathname.endsWith('/');
  const isJs = url.pathname.endsWith('.js') && sameOrigin;
  const isJson = url.pathname.endsWith('.json') && sameOrigin;

  // HTML: Network-First (أولوية للنسخة الطازجة)
  // كنا نستخدم SWR وكان يُظهر نسخة قديمة عند refresh — لذلك:
  // - نحاول الشبكة أولاً بمهلة قصيرة
  // - لو فشلت (بلا نت) → الكاش
  if (isHtml) {
    e.respondWith((async () => {
      const cache = await caches.open(STATIC_CACHE);
      try {
        const controller = new AbortController();
        const timer = setTimeout(() => controller.abort(), 4000);
        const res = await fetch(e.request, { signal: controller.signal });
        clearTimeout(timer);
        if (res && res.ok) cache.put(e.request, res.clone()).catch(() => {});
        return res;
      } catch (err) {
        const cached = await cache.match(e.request);
        return cached || fetch(e.request);
      }
    })());
    return;
  }

  // JS/JSON محلي: Stale-While-Revalidate (سرعة + تحديث خلفي)
  if (isJs || isJson) {
    e.respondWith((async () => {
      const cache = await caches.open(STATIC_CACHE);
      const cached = await cache.match(e.request);
      const fetchPromise = fetch(e.request).then(res => {
        if (res && res.ok) cache.put(e.request, res.clone()).catch(() => {});
        return res;
      }).catch(() => cached);
      return cached || fetchPromise;
    })());
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
