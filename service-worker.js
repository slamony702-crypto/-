// ═══════════════════════════════════════════════════════════
// 🗡️ Kill-Switch Service Worker
// ═══════════════════════════════════════════════════════════
// SW مُعطَّل بشكل كامل — يقوم بإلغاء نفسه ومسح جميع الكاشات
// عند تركيبه، ليضمن أن كل تحديث للسيرفر يظهر فوراً بلا وسيط.
// نُبقي هذا الملف موجوداً لسببين:
//   (1) استبدال أي SW قديم على أجهزة المستخدمين ثم إلغاء نفسه
//   (2) توفير endpoint خفيف للفحص الدوري لإصدار التطبيق
// ═══════════════════════════════════════════════════════════
const SW_VERSION = 'v125-2026-07-18-sidebar-light-theme';

self.addEventListener('install', () => {
  // اتخطَّ الانتظار وابدأ التنشيط فوراً
  self.skipWaiting();
});

self.addEventListener('activate', (e) => {
  e.waitUntil((async () => {
    try {
      // امسح كل الكاشات القديمة
      const keys = await caches.keys();
      await Promise.all(keys.map(k => caches.delete(k)));
    } catch(err) {}
    try {
      // خذ التحكم مؤقتاً لتنفيذ التنظيف
      await self.clients.claim();
    } catch(err) {}
    try {
      // أَلغِ التسجيل نهائياً
      await self.registration.unregister();
    } catch(err) {}
    try {
      // بلّغ كل الصفحات المفتوحة أن SW اختفى وأن التحديث جاهز
      const clients = await self.clients.matchAll({ type: 'window' });
      for (const client of clients) {
        try { client.postMessage({ type: 'sw-removed' }); } catch(e) {}
      }
    } catch(err) {}
  })());
});

// لا fetch handler → المتصفح يذهب مباشرة إلى الشبكة دائماً
