// ═══════════════════════════════════════════════════════════
// ⚡ Service Worker — كاش ذكي (Stale-While-Revalidate)
// ═══════════════════════════════════════════════════════════
// المشكلة السابقة: بدون كاش، كل فتحة للتطبيق كانت تنزّل ملف
// الواجهة (~2.6MB) + مكتبات CDN + الخطوط من الشبكة من الصفر —
// وهذا سبب البطء والتعليق على الموبايل.
// الحل: نعرض النسخة المخزّنة فورًا (فتح شبه لحظي) ونحدّثها في
// الخلفية. فحص الإصدار الدوري داخل التطبيق (كل 45 ثانية) يعرض
// بانر «تحديث جديد» عند نزول نسخة أحدث، وزر التحديث يمسح الكاش
// قبل إعادة التحميل — فلا يعلق أحد على نسخة قديمة.
// ملاحظة نشر: غيّر SW_VERSION مع كل نشر (نفس قيمة APP_VERSION).
// ═══════════════════════════════════════════════════════════
const SW_VERSION = 'v136-2026-07-20-delivery-apps';
const CACHE_NAME = 'sg-shell-' + SW_VERSION;

// لا تلمس أبدًا: قاعدة البيانات، دوال الخادم، فحص إصدار التطبيق، APIs خارجية حية
const NEVER_CACHE = [
  'supabase.co',
  '/api/',
  'service-worker.js',
  'generativelanguage',
  'aladhan.com'
];

// مضيفو CDN المسموح تخزينهم (مكتبات وخطوط ثابتة)
const CDN_HOSTS = /fonts\.googleapis\.com|fonts\.gstatic\.com|cdn\.jsdelivr\.net|unpkg\.com/;

self.addEventListener('install', () => {
  // فعّل النسخة الجديدة فورًا بلا انتظار
  self.skipWaiting();
});

self.addEventListener('activate', (e) => {
  e.waitUntil((async () => {
    try {
      // امسح كاشات الإصدارات القديمة فقط
      const keys = await caches.keys();
      await Promise.all(keys.filter(k => k !== CACHE_NAME).map(k => caches.delete(k)));
    } catch (err) {}
    try { await self.clients.claim(); } catch (err) {}
  })());
});

self.addEventListener('fetch', (e) => {
  const req = e.request;
  if (req.method !== 'GET') return;
  const url = req.url;
  if (NEVER_CACHE.some(s => url.includes(s))) return; // شبكة مباشرة دائمًا

  const isNav = req.mode === 'navigate';
  const sameOrigin = url.startsWith(self.location.origin);
  const isCdn = CDN_HOSTS.test(url);
  if (!isNav && !sameOrigin && !isCdn) return; // أي شيء آخر → شبكة مباشرة

  e.respondWith((async () => {
    const cache = await caches.open(CACHE_NAME);
    const cached = await cache.match(req, { ignoreSearch: isNav });

    // حدّث من الشبكة في الخلفية (أو كمصدر أساسي لو مفيش كاش)
    const networkPromise = fetch(req).then((res) => {
      // نخزّن الاستجابات السليمة فقط. opaque = سكربتات CDN بدون CORS — تخزينها آمن هنا
      if (res && (res.ok || res.type === 'opaque')) {
        cache.put(req, res.clone()).catch(() => {});
      }
      return res;
    }).catch(() => null);

    if (cached) {
      // Stale-While-Revalidate: أظهر المخزّن فورًا والشبكة تحدّث في الخلفية
      return cached;
    }
    const fresh = await networkPromise;
    if (fresh) return fresh;
    // أوفلاين ومفيش كاش لهذا الطلب: للملاحة جرّب الصفحة الرئيسية المخزّنة
    if (isNav) {
      const fallback = await cache.match('/', { ignoreSearch: true });
      if (fallback) return fallback;
    }
    return new Response('', { status: 504, statusText: 'offline' });
  })());
});
