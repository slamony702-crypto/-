# ترتيب تطبيق SQL — طبقة اعتماد طلبات الشراء

**الفرع:** `feature/purchase-orders-wave1`
**آخر تحديث:** 2026-07-18

---

## 📋 الجدول الرئيسي

| الترتيب | اسم الملف | النوع | هل تم تطبيقه؟ | البيئة | يعتمد على | النتيجة المتوقعة |
|:------:|-----------|-------|---------------|--------|-----------|------------------|
| 0 | `proc-approval-preflight.sql` | Read Only (14 فحص) | **EXECUTED LOCALLY** | Local PG 16 (localhost:55432 معزول) — 🛑 **NOT APPLIED** على Cloud | — | يعرض جاهزية Schema |
| 1 | `proc-approval-1.sql` | Migration | **EXECUTED LOCALLY** — 🛑 **NOT APPLIED** على Cloud | Local + Cloud Staging | proc-schema-1.sql (موجود من قبل) + hr-schema (موجود) | 3 جداول جديدة (approval_rules, requisition_approvals, approval_activity) + 6 RPCs + RLS |
| 2 | `proc-approval-2-hardening.sql` | Migration | **EXECUTED LOCALLY** — 🛑 **NOT APPLIED** على Cloud | Local + Cloud Staging | Migration 1 | proc_approval_settings + عمودان جديدان على proc_requisitions + 3 Triggers guards + Legacy RPC |
| 3 | `proc-approval-3-matching-priority.sql` | Migration | **EXECUTED LOCALLY** — 🛑 **NOT APPLIED** على Cloud | Local + Cloud Staging | Migration 2 | عمود priority + فهرس + إعادة كتابة proc_match_approval_rules + AMBIGUOUS_APPROVAL_RULES |
| 4 | `proc-approval-4-snapshot.sql` | Migration | **EXECUTED LOCALLY** — 🛑 **NOT APPLIED** على Cloud | Local + Cloud Staging | Migration 3 | source_rule_id + 4 أعمدة إضافية على approval_rules + snapshot موسّع في submit RPC |
| 5 | `proc-approval-5-notifications-audit.sql` | Migration | **EXECUTED LOCALLY** — 🛑 **NOT APPLIED** على Cloud | Local + Cloud Staging | Migration 4 | جدول history + 3 Triggers audit + UNIQUE PO + إشعارات مدمجة في RPCs |
| 6 | `proc-approval-6-trigger-invoker.sql` | Migration (إصلاح حرج) | **EXECUTED LOCALLY** — 🛑 **NOT APPLIED** على Cloud | Local + Cloud Staging | Migrations 1-5 | تغيير guard triggers إلى SECURITY INVOKER (يصلح current_user check) |
| 7 | `proc-approval-tests.sql` | Test (34 سيناريو + BEGIN…ROLLBACK) | **EXECUTED LOCALLY** (40/40 PASS) — 🛑 **NOT APPLIED** على Cloud | Local + Cloud Staging (بعد Migrations 1→6) | كل Migrations 1→6 | NOTICE PASS/FAIL لكل test |
| 8 | `proc-concurrency-session-a.sql` | Test — يدوي (جلسة A) | **EXECUTED LOCALLY** (PASS) — 🛑 **NOT APPLIED** على Cloud | Local + Cloud Staging (2 جلسات psql متوازيتين) | Migrations 1→6 + المستخدمون التجريبيون | Session A تعتمد الخطوة |
| 9 | `proc-concurrency-session-b.sql` | Test — يدوي (جلسة B) | **EXECUTED LOCALLY** (PASS) — 🛑 **NOT APPLIED** على Cloud | Local + Cloud Staging | Migrations 1→6 + المستخدمون التجريبيون + Session A running | Session B تحاول نفس الخطوة، تفشل بـSTEP_NOT_PENDING |
| 10 | `_reengineering/cloud-test/proc-approval-auth-seed.sql` | Seed (Cloud فقط) | **NOT APPLIED** | Cloud Staging فقط | Migrations 1→6 مطبقة | 8 مستخدمين auth تجريبيين مربوطين بـapp users |
| 11 | `_reengineering/cloud-test/proc-approval-rls-cloud-tests.sql` | Test (RLS 9-row matrix + BEGIN…ROLLBACK) | **NOT APPLIED** | Cloud Staging فقط | Migrations 1→6 + auth seed | NOTICE PASS/FAIL لـ9 اختبارات RLS بأدوار مختلفة |
| 99 | `proc-approval-rollback.sql` | Rollback | **ROLLBACK ONLY** (لا يُطبَّق إلا للتراجع) | عند الحاجة فقط | Migrations 1→6 مطبقة | يحذف كل ما أُنشئ + عمود amount_at_submit + submitted_at من proc_requisitions |

---

## 🔑 مفاتيح الحالات

- **NOT APPLIED** — لم يُطبَّق على أي قاعدة سحابية
- **APPLIED BY OWNER** — طبّقه المالك (سيُحدَّث فور إبلاغي)
- **EXECUTED LOCALLY** — شُغِّل على PostgreSQL 16 المحلي المعزول (localhost:55432) — **ليس بديلاً كاملاً لـSupabase Cloud**
- **NOT REQUIRED** — ملف تشغيلي لا يمس السحابة
- **ROLLBACK ONLY** — يُشغَّل فقط للتراجع

---

## 🛑 هل يوجد SQL فات ولم يُطبَّق؟

**نعم — كل ملفات Migration الست + الاختبارات لم تُطبَّق على أي قاعدة سحابية بعد.**

السبب: **لا يوجد Cloud Staging Project حتى الآن**. لا يمكنني إنشاؤه بدون تسجيل دخول Supabase CLI أولًا.

**لكن:** كل ملفات Migration نجحت **محليًا** (40/40 PASS + Concurrency) على PostgreSQL 16 حقيقي في cluster معزول. البُغَات الثلاثة الحرجة (advisory lock، SECURITY DEFINER، return type change) اكتُشِفت وأُصلحت هناك.

---

## 🚫 لا ملفات "فاتت" من مراحل سابقة

راجعت كل الفولدرات: `.`, `_reengineering/`, `_reengineering/cloud-test/`, `_reengineering/local-test/`. مجموع ملفات SQL للموجة = **13 ملف**، كلها موثقة في الجدول أعلاه. لا يوجد SQL يجب أن ترفعه يدويًا **الآن** لأن ما فيش target سحابي مُنشأ بعد.

---

## 📁 ملفات SQL خارج الموجة (للمرجعية فقط — لا تلمسها)

هذه موجودة على الفرع من قبل، لا صلة لها بموجة الاعتماد:
- `proc-schema-1.sql` — Schema أساسي للمشتريات (dependency، موجود على Production)
- `hr-schema.sql`, `acct-schema*.sql`, وباقي `*-schema-1.sql` — من موجات سابقة

**لا تُطبَّق هذه من قِبَلك حاليًا — مفروض موجودة على Production ومستمر عملها.**
