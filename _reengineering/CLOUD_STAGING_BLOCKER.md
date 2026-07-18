# Cloud Staging — BLOCKED

**الفرع:** `feature/purchase-orders-wave1`
**التاريخ:** 2026-07-18

# 🛑 الحكم: `BLOCKED — SUPABASE ACCOUNT AUTHORIZATION REQUIRED`

---

## ما تم فحصه تلقائيًا

| العنصر | النتيجة |
|--------|---------|
| Supabase CLI عبر `npx supabase` | ✅ متاح (v2.109.1) — لا حاجة لتثبيت |
| `SUPABASE_ACCESS_TOKEN` في البيئة | ❌ غير مضبوط |
| `supabase projects list` | ❌ رجعت `Access token not provided` |

**الاستنتاج:** لا يمكنني إنشاء مشروع Supabase Staging، ولا الاتصال بأي مشروع سحابي، ولا تطبيق SQL على السحابة، **بدون Access Token منك**.

---

## 🔹 الخطوة الوحيدة المطلوبة منك

**احصل على Access Token من Supabase Dashboard:**

1. افتح https://supabase.com/dashboard/account/tokens
2. اضغط **`Generate new token`**
3. اسم الـtoken: `shouon-cli-staging` (اسم توضيحي فقط)
4. Scope: **يُنصح باختيار `Only staging` إن أمكن.** إذا لم يتوفر تحديد الـproject، ملاحظة: هذا الـtoken يعطي وصولًا كاملًا لكل مشاريع حسابك — احتفظ به آمنًا.
5. انسخ الـtoken (يظهر مرة واحدة فقط).
6. **افتح ملفًا محليًا في مشروعك** — سأنشئه لك جاهزًا: `.env.staging.local` (لن يُتتبَّع في Git).
7. الصق الـtoken:
   ```
   SUPABASE_ACCESS_TOKEN=sbp_XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
   ```
8. أرسل لي رسالة **قصيرة بس** تقول: "الـtoken جاهز في `.env.staging.local`".

**⚠️ لا ترسل الـtoken في الشات.** أنا سأقرأه من الملف المحلي فقط.

---

## ما سأفعله تلقائيًا بمجرد وصول الـtoken

1. أشغّل `npx supabase projects list` وأتأكد ألا تشير القائمة إلى Production بالخطأ.
2. أنشئ مشروع Staging بالاسم `shouon-al-ghithaa-staging` (Free plan، region eu-central-1 افتراضيًا).
3. أنتظر ~2 دقيقة للـsetup.
4. أطبِّق migrations 1→6 عبر psql مباشرة إلى Cloud Postgres.
5. أنشئ Auth users تجريبية (requester, procurement_manager, finance_manager, inactive user، إلخ).
6. أشغّل `proc-approval-tests.sql` على Cloud + اختبار التزامن.
7. أختبر RLS مع JWT حقيقي لكل مستخدم.
8. أختبر UI (لو ممكن) على staging URL.
9. أنشئ Preview Deployment على Vercel مع env vars تشير لـStaging **فقط**.
10. أنتج التقرير النهائي `PROC_APPROVAL_CLOUD_STAGING_REPORT.md`.

**كل ما سبق آلي بعد وصول الـtoken — لا تدخل يدوي منك مطلوب لهذه الخطوات.**

---

## ما أستطيع تنفيذه الآن دون الـtoken

أشغل التالي في نفس الجلسة (المرحلة 2 من الخطة):
- ✅ `.env.example` (تم — يوجد على الفرع)
- ✅ تحصين `.gitignore` (تم)
- ✅ سكربت التطبيق التلقائي `_reengineering/cloud-test/apply.sh`
- ✅ Auth seed SQL جاهز (`proc-approval-auth-seed.sql`)
- ✅ مصفوفة RLS tests (`proc-approval-rls-cloud-tests.sql`)
- ✅ آلية UI Staging override (localStorage flag أو querystring)
- ✅ تقرير Cloud Staging Report scaffold مع verdict `BLOCKED`
- ✅ Production Migration Checklist

كل هذا يُنجز أثناء انتظار الـtoken، فور وصوله يمكن التنفيذ فورًا.

---

## القواعد المُلتزَم بها

- ❌ لن أتصل بأي مشروع سحابي بدون token صريح
- ❌ لن أستخدم `.env` القديمة أو أي مفتاح موجود قبل تأكيدك
- ❌ لن أتصل بـProduction تحت أي ظرف
- ❌ لن أطبع أي token في التقارير أو Git
- ❌ لن أفعل push أو merge أو deploy
- ✅ سأتخذ فقط قرارات لا تحتاج صلاحية سحابية حتى يصل التفويض
