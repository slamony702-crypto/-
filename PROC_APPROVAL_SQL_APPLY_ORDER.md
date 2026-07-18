# ترتيب تطبيق ملفات SQL — طبقة اعتماد طلبات الشراء

**⚠️ لا تشغّل أي ملف من هذه المجموعة على Production قبل اجتياز staging.**

---

## 🔢 الترتيب النهائي

| # | الملف | النوع | Schema Change | يستخدم `BEGIN…ROLLBACK`؟ | يجب تشغيله على Staging أولًا؟ |
|---|-------|------|---------------|--------------------------|-------------------------------|
| 0 | `proc-approval-preflight.sql` | **Read-Only** (14 فحص) | ❌ لا | ❌ لا (فقط SELECTs) | ✅ آمن على أي بيئة |
| 1 | `proc-approval-1.sql` | **Migration** | ✅ 3 جداول + 6 RPCs + RLS | ❌ (يستخدم BEGIN…COMMIT دائم) | ✅ إجباري |
| 2 | `proc-approval-2-hardening.sql` | **Migration** | ✅ 1 جدول + 2 عمود + 3 Triggers + 5 RPCs | ❌ (BEGIN…COMMIT) | ✅ إجباري |
| 3 | `proc-approval-3-matching-priority.sql` | **Migration** | ✅ 1 عمود + 1 فهرس + 2 RPCs | ❌ (BEGIN…COMMIT) | ✅ إجباري |
| 4 | `proc-approval-4-snapshot.sql` | **Migration** | ✅ 4 أعمدة + 1 عمود ربط + 3 RPCs | ❌ (BEGIN…COMMIT) | ✅ إجباري |
| 5 | `proc-approval-5-notifications-audit.sql` | **Migration** | ✅ 1 جدول + 3 Triggers + 1 فهرس فريد + 4 RPCs | ❌ (BEGIN…COMMIT) | ✅ إجباري |
| 6 | `proc-approval-tests.sql` | **Test** (25+ سيناريو) | ✅ يعدل + `ROLLBACK` في النهاية | ✅ **BEGIN…ROLLBACK** — لا يحفظ شيئًا | ✅ إجباري |
| 7 | `proc-concurrency-session-a.sql` | **Test — يدوي** (جلسة A) | ✅ يعدل — قابل للـCOMMIT أو ROLLBACK | ❌ (يمكن اختيار COMMIT أو ROLLBACK) | ✅ يشغَّل في جلستَي psql منفصلتين |
| 8 | `proc-concurrency-session-b.sql` | **Test — يدوي** (جلسة B) | ❌ لا (`ROLLBACK` في النهاية) | ✅ **BEGIN…ROLLBACK** | ✅ بالتوازي مع (7) |
| 9 | `proc-approval-rollback.sql` | **Rollback** | ✅ يسقط كل ما أنشأته 1-5 | ❌ (BEGIN…COMMIT) | 🟡 عند الحاجة فقط |

---

## 📋 خطوات التطبيق التفصيلية

### قبل التطبيق (Preflight)

**1. تأكد أن الاتصال ليس Production:**
```sql
SELECT current_database(), current_setting('server_version'),
       COALESCE(current_setting('app.settings.env', TRUE), 'unknown') AS env_hint;
```
اذا كان الاتصال بـProduction — **توقف فورًا.**

**2. شغّل `proc-approval-preflight.sql`.**
تحقق من مخرجاته:
- ✅ كل الجداول المطلوبة `EXISTS`
- ✅ `auth.uid` موجودة
- ✅ لا `NAME_CONFLICTS ALREADY EXISTS` (إلا لو تعيد تطبيق)
- ✅ الحساب `5101` موجود
- ✅ `set_updated_at()` موجودة
- 🟡 راجع `DATA_HEALTH_inflight_submitted` — قد تحتاج قرارًا لطلبات قائمة

---

### التطبيق (Migrations 1 → 5)

**بالترتيب حصريًا:**

```
1. proc-approval-1.sql
2. proc-approval-2-hardening.sql
3. proc-approval-3-matching-priority.sql
4. proc-approval-4-snapshot.sql
5. proc-approval-5-notifications-audit.sql
```

**بعد كل ملف، تحقق من قسم "قائمة التحقق" في نهايته.**

**كل الملفات:**
- **Idempotent** — يمكن إعادة تشغيلها بأمان (`IF NOT EXISTS`, `CREATE OR REPLACE`)
- **Additive** — لا حذف/تعديل مدمّر على جداول قائمة
- **Uses `BEGIN…COMMIT`** — تغييرات دائمة بعد نجاح الملف كامل

**⚠️ إذا فشل ملف في المنتصف:** الـ`COMMIT` لن يُنفَّذ — لا تغييرات دائمة. راجع الخطأ، أصلحه، وأعِد التشغيل.

---

### الاختبارات (بعد التطبيق)

**Test 6 — الاختبارات الأساسية:**
```
6. proc-approval-tests.sql
```
- يحتوي 25+ سيناريو داخل `BEGIN…ROLLBACK` — **لا يحفظ أي بيانات**.
- اقرأ رسائل `NOTICE` في المخرج — كل اختبار يطبع `PASS` أو `FAIL` أو `SKIPPED`.
- **متوقع:** إذا كل الـmigrations صحيحة و`auth.uid` تعمل، جميع الاختبارات `PASS` (باستثناء `TEST 7` الذي يُنفَّذ يدويًا في الجلستين).

**Tests 7-8 — التزامن (يدوي بجلستين):**
1. افتح `session-a.sql` في جلسة psql/SQL Editor الأولى — شغّله حتى تُطبَع `STEP_ID`.
2. عدّل `session-b.sql`: استبدل `STEP_ID_HERE` بالقيمة الفعلية.
3. افتح جلسة أخرى مستقلة — شغّل `session-b.sql`.
4. عُد للجلسة الأولى — أكمل الجزء الأخير (الاعتماد + COMMIT).
5. الجلسة الثانية ستفشل بـ`STEP_NOT_PENDING` — هذا هو **PASS**.

---

### Rollback (عند الحاجة فقط)

```
9. proc-approval-rollback.sql
```
- يحذف **كل** الجداول والدوال والـTriggers من الموجة.
- **لا يستعيد بيانات مفقودة** — استخدم Backup إذا احتجت.
- **لا يعدّل الـUI** — الواجهة ستفشل عند استدعاء RPCs المفقودة. حل: `git checkout <sha-before-wave> -- index.html.html`.

---

## 🔍 وظيفة كل ملف

### `proc-approval-preflight.sql` (Read-Only)
- 14 استعلام SELECT لفحص جاهزية البيئة قبل Migration
- يعرض: جداول قائمة، أنواع مفاتيح، حالات موجودة، تعارض أسماء، RLS الحالية، بيانات قد تفشل constraints، حساب 5101، دالة set_updated_at

### `proc-approval-1.sql`
- **الجداول:** `proc_approval_rules`, `proc_requisition_approvals`, `proc_approval_activity`
- **RPCs:** `proc_match_approval_rules`, `proc_requisition_total`, `proc_submit_requisition`, `proc_approve_step`, `proc_reject_step`, `proc_cancel_requisition_approval`, `proc_get_approval_chain`
- **RLS** على الجداول الثلاث

### `proc-approval-2-hardening.sql`
- **الجداول:** `proc_approval_settings` (single-row config)
- **أعمدة جديدة على `proc_requisitions`:** `amount_at_submit`, `submitted_at`
- **Triggers:** guards على `proc_requisitions` (منع UPDATE مباشر لـstatus عند وجود chain، منع تغيير branch/dept بعد submit، رفض بلا سبب، حالات نهائية)، guard على `proc_requisition_items` (منع تعديل بعد draft)، guard على `proc_purchase_orders` (منع PO قبل approval)
- **RPCs مُحدَّثة:** `proc_submit_requisition` (advisory lock + APPROVAL_CONFIGURATION_MISSING)، `proc_approve_step` / `proc_reject_step` / `proc_cancel_requisition_approval` (auth + active + lock)
- **RPC جديدة:** `proc_legacy_decide_requisition`

### `proc-approval-3-matching-priority.sql`
- **عمود جديد على `proc_approval_rules`:** `priority INT DEFAULT 100`
- **فهرس** للـranking السريع
- **RPCs مُحدَّثة:** `proc_match_approval_rules` (4-level tiebreak: specificity → range width → priority → updated_at)، ترفع `AMBIGUOUS_APPROVAL_RULES` عند التعادل التام
- `proc_submit_requisition` يعالج AMBIGUOUS ويسجل في activity

### `proc-approval-4-snapshot.sql`
- **عمود ربط على `proc_requisition_approvals`:** `source_rule_id BIGINT REFERENCES proc_approval_rules(id) ON DELETE SET NULL`
- **أعمدة إضافية على `proc_approval_rules`:** `description`, `allow_self_approval`, `sla_hours`, `activation_date`
- **RPCs مُحدَّثة:** `proc_match_approval_rules` (يحترم activation_date + يعيد الحقول الجديدة)، `proc_submit_requisition` (snapshot موسّع)، `proc_approve_step` (يحترم allow_self_approval من snapshot)، `proc_get_approval_chain` (يضم source_rule_id + is_active الحالية للقاعدة)

### `proc-approval-5-notifications-audit.sql`
- **جدول جديد:** `proc_approval_rules_history` (Audit CRUD للقواعد + تغييرات settings)
- **Triggers:** AFTER I/U/D على `proc_approval_rules` (يسجل التاريخ)، AFTER UPDATE على `proc_approval_settings` (يسجل legacy toggle)، BEFORE DELETE على `proc_approval_rules` (يمنع الحذف إذا استُخدمت — `RULE_IN_USE`)
- **UNIQUE partial index:** `proc_purchase_orders(requisition_id) WHERE requisition_id IS NOT NULL AND status <> 'cancelled'`
- **RPC مساعدة:** `proc_notify_step_assignees(step_id)` — يُدرج في `notifications` للمُخصَّص أو حاملي الدور
- **RPCs مُحدَّثة:** submit ← يُشعِر الخطوة الأولى فقط + إشعار إداري عند AMBIGUOUS/MISSING، approve ← يُشعِر الخطوة التالية أو صاحب الطلب عند النهاية، reject ← يُشعِر صاحب الطلب

### `proc-approval-tests.sql`
- 25+ سيناريو داخل `BEGIN…ROLLBACK`
- كل اختبار داخل `SAVEPOINT…ROLLBACK TO SAVEPOINT` (فشل واحد لا يوقف الباقي)
- يحاكي auth عبر `set_config('request.jwt.claim.sub', ..., TRUE)`
- كل رسائل PASS/FAIL/SKIPPED عبر `RAISE NOTICE`

### `proc-concurrency-session-a.sql` + `proc-concurrency-session-b.sql`
- اختبار التزامن بجلستين متوازيتين — راجع تعليمات كل ملف
- المتوقع: A ينجح، B ينتظر، ثم يفشل بـ`STEP_NOT_PENDING`

### `proc-approval-rollback.sql`
- يحذف بشكل مرتّب: Triggers → Indexes → Functions → Tables → Columns
- لا يستعيد بيانات — استخدم Backup

---

## 🚨 قيود يجب احترامها

- ❌ **لا تشغّل أي ملف من هذه المجموعة على Production قبل staging.**
- ❌ **لا تعدّل ملفات Migration مُطبَّقة — أنشئ Migration جديدة إذا احتجت تعديلًا.**
- ❌ **لا تحذف قاعدة مستخدمة — استخدم `is_active = FALSE`.**
- ❌ **لا تلمس** جداول أخرى غير `proc_*` — الموجة معزولة.
- ✅ **UI يعمل بأمان** حتى قبل تطبيق أي migration بفضل Feature Detection.

---

## 🔗 Dependencies

- `hr-schema.sql` — يجب أن يكون مُطبَّق (`users`, `current_app_user_id`, `current_app_role`)
- `acct-schema*.sql` — للـAP (`acct_vendors`, `acct_bills`)
- `proc-schema-1.sql` — الجداول الأصلية للمشتريات (PR/PO/GRN)
- Supabase Auth مفعّل (لـ`auth.uid()`)
- الدالة `set_updated_at()` موجودة (من HR أو Accounting)

---

## ✅ التحقق النهائي بعد Migrations 1-5

```sql
-- (1) 5 جداول جديدة
SELECT relname FROM pg_class WHERE relname IN (
  'proc_approval_rules',
  'proc_requisition_approvals',
  'proc_approval_activity',
  'proc_approval_settings',
  'proc_approval_rules_history'
) ORDER BY relname;
-- المتوقع: 5 صفوف

-- (2) الدوال الأساسية (11 دالة)
SELECT proname FROM pg_proc WHERE proname IN (
  'proc_match_approval_rules', 'proc_requisition_total',
  'proc_submit_requisition', 'proc_approve_step', 'proc_reject_step',
  'proc_cancel_requisition_approval', 'proc_get_approval_chain',
  'proc_legacy_decide_requisition', 'proc_notify_step_assignees',
  'proc_req_update_guard', 'proc_req_items_write_guard'
) ORDER BY proname;
-- المتوقع: 11 صفًا

-- (3) Triggers الحرس
SELECT tgname FROM pg_trigger WHERE tgname LIKE 'proc_%_guard_trg'
   OR tgname LIKE 'proc_appr_%_trg' ORDER BY tgname;
-- المتوقع: ≥6 صفوف

-- (4) القيود الفريدة
SELECT indexname FROM pg_indexes WHERE indexname = 'proc_po_unique_requisition';
-- المتوقع: 1 صف

-- (5) الإعدادات الافتراضية
SELECT allow_legacy_approval FROM proc_approval_settings WHERE id = TRUE;
-- المتوقع: FALSE (سياسة صارمة)
```

---

## 🕐 تعليمات التراجع (إذا اتخذت قرار التراجع)

1. تأكد أن التراجع مطلوب (وليس فقط إصلاح خطأ يمكن الاستمرار معه)
2. خذ Backup للجداول التي تغيّرت: `pg_dump -t proc_* > backup.sql`
3. شغّل `proc-approval-rollback.sql`
4. تحقق من قائمة `التحقق بعد Rollback` في نهاية الملف
5. أعِد UI للحالة السابقة: `git checkout <sha-before-wave> -- index.html.html`
6. راجع مركز الإشعارات — قد يوجد إشعارات معلقة عن طلبات كانت في مسار الاعتماد

---

## 📁 الفرع

كل الملفات موجودة على: **`feature/purchase-orders-wave1`** — لم يُدمج مع master بعد.
