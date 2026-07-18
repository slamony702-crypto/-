# مصفوفة واجهات الذكاء الاصطناعي — الحماية المطبّقة

**الفرع:** `security/api-hardening-phase1`

## الـEndpoints المكتشفة

| Endpoint | الغرض | الملف |
|----------|-------|-------|
| `/api/agent` | المساعد الذكي (قراءة + function calling) | `api/agent.js` |
| `/api/rewrite` | إعادة صياغة النص | `api/rewrite.js` |
| (مشترك) | helpers أمنية — ليس endpoint | `api/_security.js` |

> لم يُكتشف أي endpoint AI آخر. البحث شمل `api/**` كاملًا.

---

## الحماية المطبّقة لكل endpoint

| الحماية | `/api/agent` | `/api/rewrite` | التفاصيل |
|---------|:---:|:---:|---|
| CORS allowlist (exact) | ✅ | ✅ | من `ALLOWED_ORIGINS`، بلا wildcard/substring |
| OPTIONS preflight | ✅ | ✅ | 204 مسموح / 403 مرفوض |
| Content-Type check | ✅ | ✅ | يرفض غير `application/json` → 415 |
| Request size limit | ✅ | ✅ | agent: 120K حرف؛ rewrite: 8K حرف |
| Message count limit | ✅ | — | حد 40 رسالة |
| Rate limit | ✅ (20/دق) | ✅ (30/دق) | best-effort per instance |
| JWT scaffold | ✅ | ✅ | خلف `AI_REQUIRE_SUPABASE_JWT` |
| Production Guard | ✅ | ✅ | 503 لو الإنتاج بلا مصادقة |
| Error masking | ✅ | ✅ | لا stack/مفاتيح/model_errors للعميل |
| Request ID | ✅ | ✅ | في كل رد خطأ + اللوجز |
| Safe logging | ✅ | ✅ | لا tokens/prompts كاملة |
| No client system prompt | ✅ | ✅ | agent: promptMode allowlist؛ rewrite: mode allowlist موجود |

---

## أنماط التعليمات المسموحة (`/api/agent`)

الخادم يحوّل معرّفًا مسموحًا إلى نص موثوق. أي قيمة غير معروفة → `default`:

| المعرّف | التأثير |
|---------|---------|
| `default` | لا إضافة |
| `summarize` | ملخص موجز في نقاط |
| `operational_analysis` | تحليل تشغيلي + إبراز مخاطر |
| `report_generation` | صياغة كتقرير إداري |

**لا يُقبل أي نص حر من العميل.**

---

## متغيرات البيئة المطلوبة

| المتغير | الغرض | مثال |
|---------|-------|------|
| `GEMINI_API_KEY` | مفتاح Gemini | (سري في Vercel) |
| `ALLOWED_ORIGINS` | قائمة الأصول (فواصل) | `https://shouon-al-ghithaa.vercel.app,http://localhost:3001` |
| `AI_REQUIRE_SUPABASE_JWT` | تفعيل المصادقة | `true` في الإنتاج |
| `SUPABASE_URL` | للتحقق من التوكن | `https://<ref>.supabase.co` |
| `SUPABASE_ANON_KEY` | للتحقق من التوكن | (public) |

---

## صلاحيات AI المقترحة (لم تُنفَّذ بعد — تنتظر B1)

المواصفات طلبت صلاحيات مثل:
`ai.rewrite` / `ai.translate` / `ai.summarize` / `ai.agent.read` / `ai.agent.tools` / `ai.agent.admin`

**الحالة:** لم تُنفَّذ في هذه الجولة لأنها تعتمد على:
1. ترحيل Supabase Auth (B1) — لم يبدأ
2. جدول صلاحيات مربوط بـ`auth.uid()`

**التوصية:** تُنفَّذ ضمن موجة B1 (ترحيل المصادقة) مع RLS + Audit لكل Tool Call. مُوثَّقة كـفجوة متبقية.

---

## المسار الحالي لكل Tool Call (الوضع الفعلي)

```
مستخدم → الواجهة (بصلاحيات RLS الحالية) → /api/agent
  → الخادم لا يتصل بـDB (القاعدة الذهبية محفوظة)
  → النموذج يطلب أداة → الواجهة تنفّذها بصلاحيات المستخدم (RLS)
  → النتيجة تعود للنموذج
```

**ملاحظة:** المصادقة الكاملة (مستخدم موثق + صلاحية + نطاق فرع + Audit) تكتمل بعد B1.
حاليًا JWT scaffold جاهز لكن يُفعَّل فقط عند `AI_REQUIRE_SUPABASE_JWT=true`.
