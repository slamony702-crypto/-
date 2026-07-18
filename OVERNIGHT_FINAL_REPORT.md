# تقرير الليلة النهائي — طبقة اعتماد طلبات الشراء

**الفرع:** `feature/purchase-orders-wave1`
**عدد الـcommits:** 19
**التاريخ:** 2026-07-18
**النطاق:** طلبات الشراء + مسار الاعتماد **حصريًا** — لا موديول آخر

# 🟢 الحكم: `READY FOR MANUAL SQL APPLICATION`

الكود جاهز بالكامل للتطبيق اليدوي على بيئة اختبار Supabase. لم يُطبَّق أي SQL بواسطتي.

---

## 1) ملخص ما تم

بُنيت طبقة اعتماد **متعددة المستويات، قابلة للإعداد، مع Snapshot ثابت، وسجل تدقيق كامل، وإشعارات موجّهة** لطلبات الشراء. الطبقة **إضافية بالكامل** فوق النظام القائم:
- لا حذف/تعديل مدمّر لأي جدول موجود
- الواجهة تبقى شغّالة حتى قبل تطبيق SQL (Feature Detection)
- يمكن التراجع كاملًا بملف واحد

## 2) حالة الموديول: قبل ↔ بعد

| البُعد | قبل الموجة | بعد الموجة |
|--------|-----------|-----------|
| اعتماد PR | مُعتمِد واحد فقط (`approved_by` عمود بسيط) | 1-N مستويات قابلة للإعداد + نمط قديم محمي بـflag |
| Rule matching | لا يوجد | 4-معايير محددة + `AMBIGUOUS_APPROVAL_RULES` |
| Snapshot | لا يوجد | JSON كامل + FK للقاعدة الأصلية |
| ترتيب الخطوات | — | مُنفَّذ + advisory lock |
| Self-approval | — | ممنوع بالافتراضي + قابل للسماح لكل قاعدة |
| Concurrency | لا حماية | `pg_advisory_xact_lock` + `FOR UPDATE` + `UNIQUE` |
| تعديل الطلب بعد التقديم | مسموح | ممنوع (Triggers) |
| تحويل PO قبل الاعتماد | ممكن | ممنوع (Trigger + UNIQUE) |
| PO مكرر لنفس PR | ممكن | ممنوع (Partial UNIQUE) |
| رفض بلا سبب | ممكن | ممنوع (RPC + Trigger) |
| Audit | جزئي (activity) | كامل لكل عملية على القواعد + settings |
| Notifications | لا يوجد | متكامل: الخطوة الحالية فقط، ينتقل تلقائيًا، إشعار صاحب الطلب |
| Feature Detection | — | UI ما يتعطل قبل تطبيق SQL |
| Rollback | — | ملف واحد جاهز |

## 3) الملفات الجديدة (12 ملف)

### SQL (10 ملفات) — بترتيب التطبيق
| # | الملف | النوع | السطور |
|---|-------|------|--------|
| 1 | `proc-approval-preflight.sql` | Read-Only Preflight | ~180 |
| 2 | `proc-approval-1.sql` | Migration base | ~540 |
| 3 | `proc-approval-2-hardening.sql` | Migration hardening | ~650 |
| 4 | `proc-approval-3-matching-priority.sql` | Migration priority+AMBIGUOUS | ~275 |
| 5 | `proc-approval-4-snapshot.sql` | Migration snapshot+rule extras | ~355 |
| 6 | `proc-approval-5-notifications-audit.sql` | Migration audit+notifications | ~645 |
| 7 | `proc-approval-tests.sql` | Tests (33 حالة، BEGIN…ROLLBACK) | ~1170 |
| 8 | `proc-concurrency-session-a.sql` | Test manual | ~110 |
| 9 | `proc-concurrency-session-b.sql` | Test manual | ~55 |
| 10 | `proc-approval-rollback.sql` | Rollback كامل | ~110 |

### الوثائق (5 ملفات)
- `PROC_APPROVAL_SQL_APPLY_ORDER.md` — دليل التطبيق التفصيلي
- `OVERNIGHT_REPORT.md` — تقرير المرحلة الأولى (13 commits ago)
- `_reengineering/PROC_APPROVAL_REVIEW.md` — مراجعة أمنية شاملة
- `_reengineering/PROC_STAGING_SETUP.md` — إعداد staging
- `_reengineering/PROC_APPROVAL_STAGING_REPORT.md` — تقرير جاهزية Staging
- `OVERNIGHT_FINAL_REPORT.md` — هذا الملف

## 4) الملفات المعدَّلة (1)

- `index.html.html`:
  - PROC DAL جديد كامل: `PROC.approvals.{submit, approveStep, rejectStep, cancelRequisition, getChain, requisitionTotal, legacyDecide, rules.{list,get,create,update,toggleActive,remove,duplicate}, settings.{get,setAllowLegacy}, history.list, checkAvailability, _resetAvailability}`
  - Feature Detection مع cache
  - شاشة قواعد الاعتماد بـ11 حقلًا + duplicate + view history + banner
  - صفحة PR detail مع سلسلة الاعتماد + سجل النشاط + banner + معالجة `APPROVAL_CONFIGURATION_MISSING` و `AMBIGUOUS_APPROVAL_RULES`
  - Legacy fallback يمر عبر RPC مخصصة، لا UPDATE مباشر

## 5) الجداول (5)

| الجدول | Migration | الغرض |
|--------|-----------|-------|
| `proc_approval_rules` | 1 | مصفوفة القواعد |
| `proc_requisition_approvals` | 1 | خطوات الاعتماد لكل طلب |
| `proc_approval_activity` | 1 | سجل النشاط |
| `proc_approval_settings` | 2 | إعدادات (allow_legacy_approval) |
| `proc_approval_rules_history` | 5 | Audit لتغييرات القواعد + settings |

## 6) الأعمدة الجديدة على جداول قائمة

| العمود | الجدول | Migration |
|--------|--------|-----------|
| `amount_at_submit` | `proc_requisitions` | 2 |
| `submitted_at` | `proc_requisitions` | 2 |
| `priority` | `proc_approval_rules` | 3 |
| `source_rule_id` | `proc_requisition_approvals` | 4 |
| `description` | `proc_approval_rules` | 4 |
| `allow_self_approval` | `proc_approval_rules` | 4 |
| `sla_hours` | `proc_approval_rules` | 4 |
| `activation_date` | `proc_approval_rules` | 4 |

## 7) الـ RPCs (12 دالة)

| الدالة | Migration | الغرض |
|--------|-----------|-------|
| `proc_requisition_total` | 1 | إجمالي الطلب |
| `proc_match_approval_rules` | 1→3→4 | مطابقة القواعد + AMBIGUOUS + activation_date |
| `proc_submit_requisition` | 1→2→3→4→5 | التقديم مع إشعارات + snapshot موسّع |
| `proc_approve_step` | 1→2→4→5 | اعتماد خطوة + إشعار التالي |
| `proc_reject_step` | 1→2→5 | رفض + إشعار الطالب |
| `proc_cancel_requisition_approval` | 1→2 | إلغاء المسار |
| `proc_get_approval_chain` | 1→4 | قراءة السلسلة + snapshot |
| `proc_legacy_decide_requisition` | 2 | النمط القديم عبر RPC |
| `proc_notify_step_assignees` | 5 | إرسال إشعارات |
| `proc_req_update_guard` | 2 | Trigger fn — حماية UPDATE |
| `proc_req_items_write_guard` | 2 | Trigger fn — حماية items |
| `proc_po_creation_guard` | 2 | Trigger fn — منع PO قبل approval |
| `proc_appr_rules_history_trg_fn` | 5 | Trigger fn — سجل تغييرات القواعد |
| `proc_appr_rules_delete_guard_fn` | 5 | Trigger fn — منع الحذف عند الاستخدام |
| `proc_appr_settings_history_trg_fn` | 5 | Trigger fn — سجل legacy flag |

## 8) Triggers (8)

| Trigger | الجدول | الغرض |
|---------|--------|-------|
| `proc_req_update_guard_trg` | `proc_requisitions` | منع تغييرات ممنوعة |
| `proc_req_items_write_guard_trg` | `proc_requisition_items` | لا تعديل بعد draft |
| `proc_po_creation_guard_trg` | `proc_purchase_orders` | لا PO قبل approval |
| `proc_appr_rules_history_trg` | `proc_approval_rules` | AFTER I/U/D → history |
| `proc_appr_rules_delete_guard_trg` | `proc_approval_rules` | BEFORE DELETE → RULE_IN_USE |
| `proc_appr_settings_history_trg` | `proc_approval_settings` | AFTER UPDATE → history |
| `proc_approval_rules_updated_at` | `proc_approval_rules` | set_updated_at |
| `proc_approval_settings_updated_at` | `proc_approval_settings` | set_updated_at |

## 9) RLS Policies (10)

- `proc_approval_rules`: sel للمرتبطين، wr للمدراء
- `proc_requisition_approvals`: sel للطالب/معتمِد/مدير، wr للـadmin (بقية عبر RPC)
- `proc_approval_activity`: sel نفس النطاق، ins للـadmin
- `proc_approval_settings`: sel للجميع authenticated، wr للمدراء
- `proc_approval_rules_history`: sel للمدراء، ins للـadmin

## 10) Notifications

**السلوك المُدمَج في RPCs (Migration 5):**
- `submit`:
  - وضع multi: إشعار الخطوة الأولى فقط (assignees أو حاملي الدور)
  - وضع legacy: إشعار كل مدراء المشتريات
  - AMBIGUOUS: إشعار إداري
  - APPROVAL_CONFIGURATION_MISSING: إشعار إداري
- `approve_step`:
  - ليست الأخيرة: إشعار الخطوة التالية فقط
  - الأخيرة: إشعار صاحب الطلب "تم الاعتماد نهائيًا"
- `reject_step`: إشعار صاحب الطلب "تم رفض الطلب"

**Idempotency:** يعتمد على State Machine — كل transition يحدث مرة واحدة (advisory lock + status check).

**Source Link:** كل إشعار يحمل `link = '#proc_requisition/<id>'`.

**استخدام مركز الإشعارات القائم:** ✅ يستخدم `notifications` القائمة (user_id, title, body, link) — لا مكرر.

## 11) Audit

**ما يُسجَّل تلقائيًا في `proc_approval_rules_history`:**
- `created` — إنشاء قاعدة (new_values)
- `updated` — تعديل (old_values + new_values + changed_keys)
- `activated` / `deactivated` — تفعيل/تعطيل (سُجّل منفصل عن updated)
- `settings_changed` — تعديل allow_legacy_approval
- `delete_attempted` — أي محاولة حذف
- `delete_blocked` — عند رفض الحذف بـRULE_IN_USE

**كل سجل يحمل:** الوقت + المستخدم + دوره + الحقول المتغيرة + العنوان + القيم القديمة والجديدة كـJSON.

## 12) الاختبارات التي شُغِّلت فعلًا محليًا

| الفحص | النتيجة |
|-------|---------|
| **JavaScript syntax** لكل `<script>` في `index.html.html` | ✅ PASS (1 script, 0 errors) |
| **SQL: BEGIN/COMMIT balance** لكل ملف migration | ✅ متزنة (كل ملف رقم COMMIT = رقم BEGIN) |
| **SQL: `DROP TABLE` على جداول قائمة** | ✅ لا يوجد (باستثناء ملف rollback) |
| **SQL: `ALTER TABLE proc_requisitions`** | ✅ 2 (كلاهما `ADD COLUMN IF NOT EXISTS` في migration 2) + rollback |
| **Secret scan** (`service_role`, `password`, keys) | ✅ صفر |
| **Production URL scan** | ✅ صفر (لم يُضَف أي URL) |
| **أسماء الدوال متطابقة** بين RPCs والـUI DAL | ✅ متطابقة |

## 13) الاختبارات التي تحتاج قاعدة بيانات

**⚠️ NOT EXECUTED — REQUIRES DATABASE** لكل اختبار من هذه القائمة:

| # | السيناريو | Test ID |
|---|-----------|---------|
| 1 | no matching rule + flag off → APPROVAL_CONFIGURATION_MISSING | TEST 1, 17 |
| 2 | one level approval → approved | TEST 2 |
| 3 | three level approval → sequential | TEST 3 |
| 4 | out of order → STEP_ORDER_VIOLATED | TEST 4 |
| 5 | unauthorized approver → ROLE_MISMATCH | TEST 5 |
| 6 | duplicate approval → STEP_NOT_PENDING | TEST 6 |
| 7 | concurrent approval | manual sessions a+b |
| 8 | rejection with mandatory reason | TEST 8c |
| 9 | rejection without reason → REJECTION_REASON_REQUIRED | TEST 8a, 8b |
| 10 | resubmission after rejection → REQ_TERMINAL_STATE | TEST 9 |
| 11 | modification after submission → REQ_LOCKED_FIELDS | TEST 10a |
| 12 | line modification after submission → REQ_ITEMS_LOCKED | TEST 10b-d |
| 13 | PO before final approval → PO_BEFORE_APPROVAL | TEST 11 |
| 14 | PO after final approval | TEST 12 |
| 15 | inactive approver → USER_INACTIVE | BONUS 1 |
| 16 | self-approval prevention → SELF_APPROVAL_BLOCKED | BONUS 2 |
| 17 | legacy flag ON → legacy submit works | BONUS 3 |
| 18 | disabled rule after workflow | TEST 16 |
| 19 | two rules deterministic (specificity) | TEST 20 |
| 20 | priority tiebreaker | TEST 20b |
| 21 | ambiguous → AMBIGUOUS_APPROVAL_RULES | TEST 21 |
| 22 | 5-level approval | TEST 22 |
| 23 | snapshot immutability (rule modified) | TEST 23 |
| 24 | allow_self_approval snapshot frozen | TEST 24 |
| 25 | duplicate PO → UNIQUE violation | TEST 25 |
| 26 | RULE_IN_USE on delete | TEST 26 |
| 27 | audit: rule created | TEST 27 |
| 28 | audit: rule updated with changed_keys | TEST 28 |
| 29 | audit: deactivated vs updated action | TEST 29 |
| 30 | notification: first step notified | TEST 30 |
| 31 | notification: future steps NOT notified | TEST 31 |
| 32 | notification: transfers on approve | TEST 32 |
| 33 | notification: requester notified on approval | TEST 33 |
| 34 | notification: requester notified on rejection | TEST 34 |

**كل هذه الاختبارات جاهزة في `proc-approval-tests.sql` — تشغيلها يستغرق ~10 ثوانٍ بعد تطبيق migrations.**

## 14) المخاطر المتبقية

| # | المخاطرة | الشدة | التخفيف |
|---|---------|-------|---------|
| R1 | لم تُختبر على DB فعلية | 🟠 متوسطة | تشغيل tests بعد إعداد staging (خطوة قادمة) |
| R2 | `current_app_role()` يعتمد على قيمة عمود `users.role` — لا role hierarchy | 🟡 منخفضة | حالي: كافٍ للسيناريو. مستقبلًا: نظام دور مركّب |
| R3 | لا Delegation (G1) — إذا كان معتمد في إجازة، الخطوة تعلق | 🟡 منخفضة | مؤجَّل باتفاق سابق. حل مؤقت: admin يعيد التخصيص يدويًا |
| R4 | لا SLA enforcement — العمود موجود، لكن لا trigger أو job يفعّله | 🟡 منخفضة | تقارير BI مستقبلًا |
| R5 | إشعارات: لا Real-time — تظهر عند refresh فقط (طبيعة النظام الحالي) | 🟢 معلوم | خارج نطاق الموجة |
| R6 | ما زالت `Vercel Functions` (`/api/rewrite`, `/api/agent`) بلا CORS/Bearer — لا يمس هذه الموجة | 🔴 حرجة (Existing) | مذكور في `PROC_APPROVAL_REVIEW.md §15/G5` — يلزم Security Foundation قبل Preview |

## 15) القرارات المطلوبة منك

| # | القرار | الافتراضي الحالي | الخيار البديل |
|---|--------|-----------------|--------------|
| D1 | هل تفعّل `allow_legacy_approval` مؤقتًا في staging عند التجربة الأولى؟ | مُعطَّل | تفعيل مؤقت للتجربة قبل إضافة القواعد |
| D2 | هل ترغب في إضافة قاعدة افتراضية (all-branches, procurement_manager) عند التطبيق؟ | لا (تُدخِلها بنفسك) | إضافة SQL seed اختياري |
| D3 | هل تحتاج notifications عبر WhatsApp/Email؟ | فقط `notifications` القائمة | Migration مستقلة للـintegrations |
| D4 | ما هي عتبات المبالغ التي تفصل بين مستويات الاعتماد في شركتك؟ | مفتوحة (تُدخِلها في القواعد) | — |

## 16) خطوات التطبيق عندما تستيقظ

**اقرأ `PROC_APPROVAL_SQL_APPLY_ORDER.md` أولًا للتفاصيل.** الملخص السريع:

1. **أنشئ Supabase staging** (Branch أو Project جديد) — تعليمات في `_reengineering/PROC_STAGING_SETUP.md`
2. **افتح SQL Editor** على staging
3. **شغّل `proc-approval-preflight.sql`** — راجع النتائج (كل شيء EXISTS، لا CONFLICTS)
4. **شغّل بالتسلسل:**
   ```
   proc-approval-1.sql
   proc-approval-2-hardening.sql
   proc-approval-3-matching-priority.sql
   proc-approval-4-snapshot.sql
   proc-approval-5-notifications-audit.sql
   ```
5. **شغّل `proc-approval-tests.sql`** — راجع رسائل NOTICE (PASS/FAIL/SKIPPED)
6. **اختبار التزامن:** افتح جلستَي SQL Editor، اتبع تعليمات `proc-concurrency-session-a.sql` و `-b.sql`
7. **اختبار Auth (G5) يدوي:** سجل دخول بمستخدم Supabase Auth حقيقي، جرّب سيناريو كامل عبر UI
8. **إرسل لي مخرجات كل خطوة** — سأحلل النتائج وأصلح أي فشل عبر Migration جديدة (6, 7, …) على نفس الفرع.

## 17) خطوات التراجع

**إذا احتجت تراجع كامل:**
```
1. شغّل proc-approval-rollback.sql على staging
2. تحقق من قسم "التحقق بعد Rollback" في الملف
3. UI: git checkout <sha-before-wave> -- index.html.html (اختياري)
```

**إذا أردت تصحيحًا جزئيًا:**
- لا تعدّل Migration مُطبَّق — أنشئ Migration رقم 6 على نفس الفرع
- كل التغييرات Idempotent (`CREATE OR REPLACE`, `ADD COLUMN IF NOT EXISTS`) فيمكن إعادة التطبيق

## 18) Git commits (19)

```
ea7dc0a fix(procurement): remove stray COMMIT in migration 5 (out of transaction)
f1aee46 test(procurement): tests 22-34 covering migrations 4+5
a86f9b2 feat(procurement): UI feature detection + expanded rules admin + PR banner
2b2846c docs+ops(procurement): rollback SQL + apply order guide
ff7fc7f feat(procurement): Migration 4 (snapshot+rule extras) + 5 (audit+notifications)
b938ce0 docs(procurement): staging report — BLOCKED NO STAGING ENVIRONMENT
c31efcd test(procurement): extend tests + concurrency session scripts
4e6c99d feat(procurement): UI priority field + AMBIGUOUS_APPROVAL_RULES handling
4b7bf0e feat(procurement): priority + deterministic tiebreak + AMBIGUOUS detection
6bb3c34 chore(procurement): staging setup guide + read-only preflight SQL
70d0347 docs(procurement): review doc + 12 test scenarios (rollback-safe)
81b3652 feat(procurement): DAL/UI honor legacy flag, route legacy through RPC
0c3c67f feat(procurement): harden approval — hard fail, triggers, locks, legacy RPC
f42323c docs(overnight): finalize report with stop points and merge recommendation
a31eba3 feat(procurement): add approval rules admin page + dashboard link
c6bc604 feat(procurement): PR detail page renders approval chain + step actions
2dc4253 feat(procurement): extend PROC DAL with approval namespace
3114068 feat(procurement): add multi-level approval SQL layer (additive)
4af2e46 chore(overnight): scaffold overnight report and reengineering folder
```

---

## 19) الالتزام بالقواعد

- ✅ لم تُطبَّق أي SQL على أي قاعدة بيانات (Production ولا Staging)
- ✅ لم يُنفَّذ Push
- ✅ لم يُنفَّذ Merge
- ✅ لم يُنشر على Vercel
- ✅ لم يُلمَس أي موديول آخر
- ✅ الاختبارات: مصنّفة صراحة (شُغّلت محليًا / تحتاج DB — NOT EXECUTED)
- ✅ لا Secrets في Git
- ✅ لا Production URL جديد
- ✅ لا `ALTER`/`DROP` غير مقصود
- ✅ Feature Detection: الواجهة تعمل حتى قبل تطبيق SQL

---

# 🟢 الحكم: `READY FOR MANUAL SQL APPLICATION`
