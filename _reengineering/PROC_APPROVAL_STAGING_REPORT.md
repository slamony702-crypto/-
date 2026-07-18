# تقرير جاهزية طبقة اعتماد طلبات الشراء — Staging

**الفرع:** `feature/purchase-orders-wave1`
**التاريخ:** 2026-07-18
**المرحلة:** ما قبل Staging (فحص + إعداد أدوات)

---

## 🎯 الحكم النهائي

# `BLOCKED NO STAGING ENVIRONMENT`

**السبب:** لا توجد بيئة اختبار Supabase مؤكدة في المشروع الحالي. الالتزام بالقواعد يقتضي عدم الاتصال بـProduction تحت أي ظرف. الأدوات جاهزة لكن تنتظر إعداد بيئة staging من قِبَلك.

---

## 1) اسم بيئة الاختبار

**غير موجود.**

- ❌ لا `.env` files على القرص
- ❌ لا متغيرات `SUPABASE_TEST_URL`, `SUPABASE_STAGING_URL`
- ❌ لا `SUPABASE_TEST_SERVICE_ROLE_KEY`, `SUPABASE_STAGING_SERVICE_ROLE_KEY`
- ❌ لا `TEST_DATABASE_URL`, `STAGING_DATABASE_URL`
- ❌ لا `.env.example` أو `.env.sample` كـtemplate
- ✅ Vercel project واحد: `prj_zHeDQheJ904Mh82GY6mbkHlxSQRh` (name: `shouon-al-ghithaa`) — **Production فقط**
- ✅ في `api/agent.js` و `api/rewrite.js`: `process.env.GEMINI_API_KEY` فقط — لا مرجع لبيئة اختبار

**الإجراء المطلوب منك:** راجع `_reengineering/PROC_STAGING_SETUP.md` لخطوات إنشاء بيئة staging.

---

## 2) Project Ref غير الحساس

**غير متاح بعد** — لا يوجد staging project ليُذكر.

---

## 3) migrations المطبقة

**لم يُطبَّق شيء على أي قاعدة بيانات.** الملفات جاهزة على الفرع:

| # | الملف | الوصف | يجب تطبيقه على |
|---|-------|-------|----------------|
| 0 | `proc-approval-preflight.sql` | Read-only preflight (14 فحص) | Staging (آمن على أي بيئة) |
| 1 | `proc-approval-1.sql` | Wave 1 base — 3 جداول + 6 RPCs + RLS | Staging |
| 2 | `proc-approval-2-hardening.sql` | Triggers + advisory locks + legacy RPC + settings | Staging |
| 3 | `proc-approval-3-matching-priority.sql` | Priority + AMBIGUOUS_APPROVAL_RULES | Staging |

**لن يُطبَّق أي منها على Production حتى بعد نجاح كل الاختبارات وقرارك الصريح.**

---

## 4) نتائج Preflight

**لم تُشغَّل.** الملف `proc-approval-preflight.sql` جاهز لتشغيله بمجرد توفر staging.

يفحص:
- الجداول الأصلية المطلوبة (14 جدولًا: users, branches, departments, proc_*, acct_*)
- أنواع مفاتيح `id`, `requested_by`, `branch_id`, `auth_id`
- توزيع الحالات في `proc_requisitions`
- تعريف `current_app_user_id()` / `current_app_role()` / `is_procurement_manager()`
- توفر `auth.uid()` (Supabase Auth)
- سياسات RLS الحالية على جداول المشتريات
- تعارض أسماء (11 كيان نتحقق منه)
- بيانات قد تفشل constraints
- الأدوار الحالية والمستخدمون النشطون
- حساب 5101 والدالة `set_updated_at()`

---

## 5) نتائج G5 (AUTH / RLS)

**لم تُنفَّذ.** التنفيذ يتطلب:
- مستخدم Supabase Auth حقيقي على staging
- تسجيل دخول عبر UI (لبناء JWT)
- استدعاء RPCs من Supabase Client

راجع القسم "رابعًا" في مواصفات المهمة: 8 نقاط اختبار (auth.uid صحيح، active/inactive، بلا session، فرع آخر، تلاعب localStorage، استدعاء RPC مباشر).

**الحالة الحالية:** الفحص السكوني (static code review) في `_reengineering/PROC_APPROVAL_REVIEW.md §G5` أثبت أن `current_app_user_id()` تعتمد على `auth.uid()` (JWT) بشكل صحيح. لكن التنفيذ الفعلي مؤجل حتى توفر staging.

---

## 6) نتائج كل اختبار (1-20)

**لم تُشغَّل.** `proc-approval-tests.sql` يحتوي 20 اختبارًا (+2 داخلية إضافية) جاهزة للتشغيل:

| # | السيناريو | الملف | الحالة |
|---|-----------|-------|--------|
| 1 | no matching rule | TEST 1 | ⏸ pending staging |
| 2 | one level approval | TEST 2 | ⏸ pending staging |
| 3 | three level approval | TEST 3 | ⏸ pending staging |
| 4 | out of order approval | TEST 4 | ⏸ pending staging |
| 5 | unauthorized approver | TEST 5 | ⏸ pending staging |
| 6 | duplicate approval | TEST 6 | ⏸ pending staging |
| 7 | concurrent approval | session-a/b scripts | ⏸ pending staging + manual sessions |
| 8 | rejection with mandatory reason | TEST 8c | ⏸ pending staging |
| 9 | rejection without reason | TEST 8a, 8b | ⏸ pending staging |
| 10 | resubmission after rejection | TEST 9 | ⏸ pending staging |
| 11 | modification after submission | TEST 10a | ⏸ pending staging |
| 12 | line item modification after submission | TEST 10b, 10c, 10d | ⏸ pending staging |
| 13 | conversion to PO before final approval | TEST 11 | ⏸ pending staging |
| 14 | conversion to PO after final approval | TEST 12 | ⏸ pending staging |
| 15 | inactive approver | BONUS 1 | ⏸ pending staging |
| 16 | disabled rule after workflow creation | TEST 16 | ⏸ pending staging |
| 17 | legacy fallback disabled | TEST 17 | ⏸ pending staging |
| 18 | legacy fallback enabled intentionally | BONUS 3 | ⏸ pending staging |
| 19 | self approval prevention | BONUS 2 | ⏸ pending staging |
| 20 | two matching rules — deterministic | TEST 20 | ⏸ pending staging |
| 20b | priority tiebreaker | TEST 20b | ⏸ pending staging |
| 21 | AMBIGUOUS_APPROVAL_RULES on total tie | TEST 21 | ⏸ pending staging |

---

## 7) نتيجة اختبار التزامن

**لم يُنفَّذ.** السكربتان `proc-concurrency-session-a.sql` و `proc-concurrency-session-b.sql` جاهزان.

**السلوك المتوقع (بعد التنفيذ):**
1. Session A: تُنشئ الطلب والقاعدة والخطوة، ثم تعتمد الخطوة، ثم COMMIT
2. Session B (بالتوازي، على نفس الخطوة): تنتظر عند `pg_advisory_xact_lock`
3. بعد Commit A، تُطلَق قفل، B تكمل، تفحص status → ترى approved → تفشل بـ`STEP_NOT_PENDING`

**النتيجة المطلوبة:** اعتماد ينجح مرة واحدة فقط، لا سجل مكرر، لا PO مزدوج.

---

## 8) نتائج UI

**لم تُختبَر يدويًا.** المسارات جاهزة:
- `#proc_approval_rules` — شاشة إدارة القواعد (مع priority، legacy toggle)
- `#proc_requisition/:id` — صفحة تفاصيل الطلب (مع سلسلة الاعتماد، سجل النشاط، أزرار حسب الخطوة الحالية)

Screenshots في `_reengineering/screenshots/procurement-approval/` — **مجلد فارغ** حتى يتوفر staging.

---

## 9) الثغرات المكتشفة في هذه الجولة

**قبل هذه الجولة** كان `proc_match_approval_rules` يستخدم `ROW_NUMBER()` مع tiebreaker على `rule_id ASC` فقط. ذلك عمليًا يعطي نتيجة deterministic لكنه **ليس واضحًا** ولا يعطي المالك سيطرة.

**الثغرات المُغلَقة في هذه الجولة:**
| # | الثغرة | الحل |
|---|--------|------|
| V1 | الترتيب بين قاعدتين متساويتين في التخصيص غير موثّق ولا يعبّر عن نية المالك | إضافة عمود `priority` كـtiebreaker صريح، ورفع `AMBIGUOUS_APPROVAL_RULES` عند التعادل التام |
| V2 | لا اختبار صريح لسلوك "تعطيل قاعدة بعد إنشاء سلسلة" | إضافة TEST 16 — يتحقق من ثبات `rule_snapshot` |
| V3 | اختبار التزامن كان `SKIPPED` بلا خطوات عملية | إنشاء session-a/b scripts مع تعليمات psql/SQL Editor واضحة |
| V4 | لم تكن آلية اختبار "priority" مصممة (العمود غير موجود) | إضافة العمود + رسالة توضيحية في UI |

**الثغرات المتبقية (موثقة في `PROC_APPROVAL_REVIEW.md §15`):**
- **G1** Delegation — مؤجَّل بأمر صريح منك
- **G2** Notifications للمعتمد التالي — يُنفَّذ بعد نجاح الاختبارات
- **G4** Manual step reassignment — مؤجَّل بأمر صريح منك
- **G6** Audit لقواعد الاعتماد نفسها — يُنفَّذ بعد نجاح الاختبارات

---

## 10) الإصلاحات

**لم يُطلَب إصلاح بعد** — لأن الاختبارات لم تُشغَّل. عند وصول نتائج تشغيل، أي فشل سيتحول إلى:
- Migration إضافية جديدة (`proc-approval-4-*.sql`) — لن أعدّل Migration مُطبَّق
- Commit مستقل لكل إصلاح جوهري
- إعادة تشغيل كامل الاختبارات بعد كل إصلاح

---

## 11) الملفات المتغيرة في هذه الجولة

| النوع | الملف | الوصف |
|-------|------|-------|
| ➕ جديد | `_reengineering/PROC_STAGING_SETUP.md` | خطوات إعداد Staging |
| ➕ جديد | `_reengineering/PROC_APPROVAL_STAGING_REPORT.md` | هذا التقرير |
| ➕ جديد | `proc-approval-preflight.sql` | preflight قراءة فقط (14 فحص) |
| ➕ جديد | `proc-approval-3-matching-priority.sql` | Migration 3 (priority + AMBIGUOUS) |
| ➕ جديد | `proc-concurrency-session-a.sql` | جلسة A لاختبار التزامن |
| ➕ جديد | `proc-concurrency-session-b.sql` | جلسة B لاختبار التزامن |
| ✏️ معدّل | `index.html.html` | إضافة حقل priority + معالجة AMBIGUOUS في UI |
| ✏️ معدّل | `proc-approval-tests.sql` | إضافة اختبارات 16, 17, 20, 20b, 21 |

**غير مُنشأ (بانتظار staging):**
- `_reengineering/PROC_AUTH_VERIFICATION.md` — يتطلب تنفيذ فعلي
- `_reengineering/screenshots/procurement-approval/` — يتطلب فتح الواجهة

---

## 12) Git commits الجديدة في هذه الجولة

| Commit | التغيير |
|--------|---------|
| `6bb3c34` | staging setup guide + read-only preflight SQL |
| `4b7bf0e` | priority + deterministic tiebreak + AMBIGUOUS detection (SQL) |
| `4e6c99d` | UI priority field + AMBIGUOUS handling |
| `c31efcd` | extended tests + concurrency session scripts |

**إجمالي في الفرع منذ إنشائه:** 13 commit — 0 push — 0 merge — 0 production deploy.

---

## 13) Rollback instructions (بعد التطبيق على staging)

إذا احتجت التراجع عن migrations هذه الموجة على staging:

```sql
-- ⚠️ Rollback ORDER — عكس ترتيب التطبيق
BEGIN;

-- 1) Drop triggers on existing tables
DROP TRIGGER IF EXISTS proc_req_update_guard_trg      ON proc_requisitions;
DROP TRIGGER IF EXISTS proc_req_items_write_guard_trg ON proc_requisition_items;
DROP TRIGGER IF EXISTS proc_po_creation_guard_trg     ON proc_purchase_orders;

-- 2) Drop new functions
DROP FUNCTION IF EXISTS proc_req_update_guard();
DROP FUNCTION IF EXISTS proc_req_items_write_guard();
DROP FUNCTION IF EXISTS proc_po_creation_guard();
DROP FUNCTION IF EXISTS proc_legacy_decide_requisition(BIGINT, TEXT, TEXT);
DROP FUNCTION IF EXISTS proc_submit_requisition(BIGINT);
DROP FUNCTION IF EXISTS proc_approve_step(BIGINT, TEXT);
DROP FUNCTION IF EXISTS proc_reject_step(BIGINT, TEXT);
DROP FUNCTION IF EXISTS proc_cancel_requisition_approval(BIGINT, TEXT);
DROP FUNCTION IF EXISTS proc_get_approval_chain(BIGINT);
DROP FUNCTION IF EXISTS proc_match_approval_rules(NUMERIC, BIGINT, BIGINT);
DROP FUNCTION IF EXISTS proc_requisition_total(BIGINT);

-- 3) Drop new tables (CASCADE يحذف policies والـFKs)
DROP TABLE IF EXISTS proc_approval_activity      CASCADE;
DROP TABLE IF EXISTS proc_requisition_approvals  CASCADE;
DROP TABLE IF EXISTS proc_approval_rules         CASCADE;
DROP TABLE IF EXISTS proc_approval_settings      CASCADE;

-- 4) Drop added columns on proc_requisitions
ALTER TABLE proc_requisitions
  DROP COLUMN IF EXISTS amount_at_submit,
  DROP COLUMN IF EXISTS submitted_at;

COMMIT;

-- التحقق
SELECT tgname FROM pg_trigger WHERE tgname LIKE 'proc_%_guard_trg';
SELECT proname FROM pg_proc WHERE proname LIKE 'proc_%approv%';
SELECT relname FROM pg_class WHERE relname LIKE 'proc_appr%';
-- الثلاثة يجب أن تعود فارغة
```

**ملاحظة:** الـUI في `index.html.html` يظل يستدعي RPCs بأسماء `proc_submit_requisition` إلخ — بعد Rollback، ستفشل UI بـ `function does not exist`. لعزل UI بعد Rollback، أوقف زر التقديم مؤقتًا أو ارجع لـcommit سابق للفرع.

---

## 14) هل الفرع جاهز للـPreview؟

# 🚫 **NOT READY** — الحكم: `BLOCKED NO STAGING ENVIRONMENT`

**الأسباب:**
1. لا بيئة اختبار مؤكدة (البند الأول من مواصفات المهمة)
2. الاختبارات الـ20 لم تُشغَّل فعليًا
3. اختبار التزامن لم يُنفَّذ
4. تحقق G5 (Auth/RLS مع Supabase Auth حقيقي) لم يُنفَّذ
5. لم يتم فحص الواجهة بصريًا على staging

**المطلوب لرفع الحكم إلى `READY FOR PREVIEW`:**
1. ✅ إعداد staging (خيار (أ) أو (ب) في `PROC_STAGING_SETUP.md`)
2. ✅ إرسال Project Ref غير الحساس + تأكيد `STAGING_IS_PRODUCTION=false`
3. ✅ تشغيل preflight → مراجعة النتائج معًا
4. ✅ تطبيق migrations 1, 2, 3 على staging
5. ✅ تشغيل `proc-approval-tests.sql` → إرسال نتائج NOTICE
6. ✅ تشغيل جلستي التزامن → إرسال النتائج
7. ✅ تنفيذ G5 (Auth) — يدوي عبر UI + إرسال screenshots
8. ✅ فحص UI على desktop/mobile — إرسال screenshots

بعد كل ذلك: إذا 22/22 اختبار PASS، الحكم يتحدّث إلى **`READY FOR PREVIEW`**.

---

## 15) قواعد المُلتزم بها في هذه الجولة

- ✅ لا اتصال بأي قاعدة بيانات
- ✅ لا تطبيق SQL على أي بيئة
- ✅ لا push إلى main
- ✅ لا merge
- ✅ لا Production deploy
- ✅ لا موديول جديد
- ✅ لا إضافة مزايا خارج نطاق الاعتماد
- ✅ G1 (Delegation) لم يُنفَّذ — مؤجَّل
- ✅ G4 (Manual reassignment) لم يُنفَّذ — مؤجَّل
- ✅ G2 (Notifications) لم يُنفَّذ — ينتظر نجاح الاختبارات
- ✅ G6 (Rules audit) لم يُنفَّذ — ينتظر نجاح الاختبارات
- ✅ لا secrets أو keys في Git أو رسائل

---

**التوقيع:** أُنجزت مهمة "إعداد Staging + التحضيرات + الأدوات". أنتظر منك تفاصيل staging لبدء المرحلة التالية.
