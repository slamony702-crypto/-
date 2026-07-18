# تقرير تصلّب واجهات الذكاء الاصطناعي — Phase 1

**الفرع:** `security/api-hardening-phase1`
**التاريخ:** 2026-07-18
**النطاق:** B3 (حقن التعليمات) + B2 (حماية الـAPI). **B1 (password_plain) لم يبدأ في هذه الجولة.**

# 🟢 الحكم: `READY FOR SECURITY REVIEW`

كل ما يمكن فحصه محليًا نجح (18/18). لا يُنشر على Production. الحالات المعتمدة على Supabase Auth مؤجّلة وموثّقة.

---

## 1) ما تم إنجازه

### B3 — إغلاق حقن التعليمات ✅
- الخادم **لا يقرأ `extraInstructions` من العميل نهائيًا** (تم حذفه من destructuring الـbody).
- بديله: `promptMode` معرّف من قائمة مسموحة server-side (`default`, `summarize`, `operational_analysis`, `report_generation`). أي قيمة أخرى → `default`.
- تعليمات النظام محفوظة server-side بالكامل.
- الواجهة لم تعد ترسل أي نص تعليمات — تمرر `'default'` فقط.
- شاشة إعدادات الأدمن: حقل "تعليمات إضافية" مُعلَّم صراحة **⏸ معطّل مؤقتًا لأسباب أمنية**.

### B2 — حماية الـAPI ✅
- **CORS:** allowlist صارم من `ALLOWED_ORIGINS` (Exact match، بلا `*`، بلا `includes`). أزيل `Access-Control-Allow-Origin: *` من الملفين.
- **OPTIONS:** 204 للمسموح، 403 للمرفوض.
- **Rate limit:** best-effort in-memory (agent 20/دق، rewrite 30/دق).
- **Content-Type:** يرفض غير JSON → 415.
- **حدود الحجم:** agent 120K حرف + 40 رسالة؛ rewrite 8K حرف.
- **Error masking:** لا stack، لا رسائل مزوّد خام، لا `model_errors` للعميل. تُسجَّل server-side مع Request ID.
- **JWT scaffold حقيقي:** `verifySupabaseJWT` يتحقق عبر `/auth/v1/user`. خلف `AI_REQUIRE_SUPABASE_JWT`.
- **Production Guard:** الإنتاج + بلا مصادقة → 503 محظور (لا API مكشوف).

---

## 2) الأسئلة المطلوبة في التقرير

| السؤال | الإجابة |
|--------|---------|
| اسم الفرع | `security/api-hardening-phase1` |
| عدد Commits | 5 (سيُحدَّث بعد commit التقارير) |
| هل `extraInstructions` أزيلت بالكامل | ✅ نعم — الخادم لا يقرأها، الواجهة لا ترسلها، `checkDailyLimit` لا يعيدها |
| نتيجة CORS | ✅ allowlist صارم، لا wildcard، اختُبر (T1-T4 PASS) |
| نتيجة Rate Limit | ✅ يعمل — 429 بعد التجاوز (T11 PASS) |
| حالة JWT الفعلية | 🟡 scaffold حقيقي جاهز، **يعمل فقط عند `AI_REQUIRE_SUPABASE_JWT=true`**. لم يُختبَر بتوكن حقيقي (يحتاج Staging) |
| الاختبارات المنفّذة | 18 PASS فعلي |
| الاختبارات المؤجّلة | 3 (valid Bearer، صلاحية AI، timeout) — تحتاج Auth Staging/Gemini حي |
| هل التغييرات تكسر الاستخدام الحالي | 🟡 جزئيًا — راجع القسم 4 |
| الحكم | `READY FOR SECURITY REVIEW` |

---

## 3) الملفات المتغيرة

| الملف | التغيير |
|-------|---------|
| `api/_security.js` | **جديد** — helpers أمنية مشتركة |
| `api/agent.js` | CORS + limits + JWT + promptMode allowlist + masking |
| `api/rewrite.js` | CORS + limits + JWT + masking |
| `index.html.html` | إزالة extraInstructions + Bearer token + معالجة 401/403/503 + ملاحظة الأدمن |
| `.gitignore` | تحصين `.env*` |
| `.env.example` | **جديد** — قالب المتغيرات |
| `_reengineering/security/*.md` | التقارير + الاختبارات |

---

## 4) ⚠️ هل تكسر الاستخدام الحالي؟ (مهم)

**نعم جزئيًا — بشكل مقصود وآمن:**

1. **حقل "تعليمات إضافية" في إعدادات المساعد لم يعد يؤثر على المساعد.** يُحفَظ في DB لكن لا يُطبَّق (حتى ترحيل B1). مُعلَّم للأدمن بوضوح.

2. **عند تفعيل `AI_REQUIRE_SUPABASE_JWT=true` قبل ترحيل B1:** المساعد سيطلب توكن Supabase صالح. المستخدمون الذين يعتمدون على `verify_login` القديم (بلا حساب Auth) **لن يستطيعوا استخدام المساعد** حتى يُنشأ لهم حساب Auth.
   - **لهذا التوصية:** أبقِ `AI_REQUIRE_SUPABASE_JWT=false` حتى يكتمل B1، مع الاعتماد على Production Guard الذي يمنع نشر الإنتاج بلا مصادقة.

3. **CORS:** لو `ALLOWED_ORIGINS` غير مضبوط في Vercel، ستُرفض الطلبات في الإنتاج (fail-closed). **يجب ضبطه قبل النشر.**

**لا كسر صامت:** كل الحالات تُظهر رسالة عربية واضحة («خدمة الذكاء الاصطناعي متوقفة مؤقتًا لحين استكمال إعدادات الأمان»).

---

## 5) المخاطر المتبقية

| # | الخطر | الشدة | ملاحظة |
|---|-------|-------|--------|
| R1 | Rate limit in-memory (per instance) | 🟡 | للإنتاج الجاد: Upstash/Redis. موثّق |
| R2 | JWT لم يُختبَر بتوكن حقيقي | 🟡 | يحتاج Staging (B1) |
| R3 | صلاحيات AI (`ai.*`) لم تُنفَّذ | 🟡 | تحتاج B1 + جدول صلاحيات |
| R4 | **B1 (password_plain) لم يبدأ** | 🔴 | الحاجز الأكبر — لم يُطلب في هذه الجولة |

---

## 6) ما لم يُنفَّذ (خارج نطاق هذه الجولة صراحةً)
- ❌ B1 — ترحيل password_plain (بأمر المالك: مؤجّل)
- ❌ صلاحيات AI الدقيقة (تعتمد على B1)
- ❌ Push / Merge / Production Deploy

---

## 7) خطوات النشر الآمن لاحقًا (للمرجعية)
1. أنشئ Staging + رحّل Auth (B1).
2. اضبط `ALLOWED_ORIGINS` + `SUPABASE_URL` + `SUPABASE_ANON_KEY` في Vercel.
3. فعّل `AI_REQUIRE_SUPABASE_JWT=true`.
4. اختبر T7/T8 بتوكن حقيقي.
5. انشر على Preview أولًا، ثم Production.

---

# 🟢 الحكم النهائي: `READY FOR SECURITY REVIEW`
