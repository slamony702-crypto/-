# UI Staging Quickstart

**الغرض:** تشغيل الواجهة على بيئة Supabase Staging **بدون** تعديل قيم Production في Git.

---

## طريقة 1 — URL parameter (الأسرع)

```
https://shouon-al-ghithaa.vercel.app/?staging=1
```

يعمل مرة واحدة، ثم يحفظ `sg_env=staging` في localStorage للجلسات القادمة.

**للرجوع للـProduction:**
```
https://shouon-al-ghithaa.vercel.app/?staging=0
```

---

## طريقة 2 — localStorage يدوي (DevTools)

1. افتح UI في المتصفح
2. F12 → Console
3. ضع URL + anon key الخاصين بـstaging:
   ```js
   localStorage.setItem('sg_env', 'staging');
   localStorage.setItem('sg_staging_url', 'https://<STAGING_REF>.supabase.co');
   localStorage.setItem('sg_staging_anon', 'sb_publishable_STAGING_ANON_KEY_HERE');
   location.reload();
   ```
4. ستظهر شارة `STAGING` صفراء في أعلى يسار الصفحة.

**⚠️ لا تُلصَق هذه القيم في Git.** توجد فقط في localStorage للمتصفح.

---

## طريقة 3 — تشغيل محلي (Preview بلا Deploy)

```bash
# 1) شغّل Vercel dev بمتغيرات Staging
cd shouon-al-ghithaa
source .env.staging.local  # يحمّل STAGING_URL, STAGING_ANON_KEY
export UI_STAGING_MODE=true
npx vercel dev --listen 3001
```

ثم افتح http://localhost:3001?staging=1

**⚠️ لا تُنفَّذ `vercel dev` كـ`vercel --prod` حتى تكتمل الاختبارات على Staging.**

---

## التحقق من البيئة النشطة

**من Console:**
```js
console.log('Env:', CURRENT_ENV);
console.log('URL:', SUPABASE_URL);
```

**من UI:** لو شارة `STAGING` صفراء ظاهرة في الزاوية العلوية اليسرى، البيئة staging.

---

## الرجوع الطارئ للـProduction

```js
localStorage.removeItem('sg_env');
localStorage.removeItem('sg_staging_url');
localStorage.removeItem('sg_staging_anon');
location.reload();
```

---

## الأمان

- ✅ Production URL/key في الكود لا تتغير — تبقى كـfallback
- ✅ Staging URL/key **لا يوجدان في Git** — فقط في localStorage للـدولوبر
- ✅ شارة بصرية واضحة تمنع الخلط بين البيئتين
- ✅ لو نسيت مسح localStorage، فتح URL بـ`?staging=0` يرجعك لـProduction فورًا
