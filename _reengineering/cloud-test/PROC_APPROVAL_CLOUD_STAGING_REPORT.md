# Cloud Staging Report — Procurement Approval

**الفرع:** `feature/purchase-orders-wave1`
**التاريخ:** 2026-07-18 (Draft — pending owner authorization)

# 🛑 الحكم الحالي: `BLOCKED — SUPABASE ACCOUNT AUTHORIZATION REQUIRED`

**السبب:** Supabase CLI متاح (v2.109.1) لكن `SUPABASE_ACCESS_TOKEN` غير مُدَّم في البيئة. لا يمكن إنشاء مشروع staging أو تطبيق SQL على السحابة بدون تفويض منك.

**راجع `_reengineering/CLOUD_STAGING_BLOCKER.md` للخطوة الوحيدة المطلوبة منك.**

---

## 1) Project Info (سيُملأ بعد التفويض)

| الحقل | القيمة |
|-------|-------|
| Project Name | `shouon-al-ghithaa-staging` (مقترح) |
| Project Ref | _(pending)_ |
| Region | _(pending — الاقتراح: eu-central-1)_ |
| URL | _(pending)_ |
| Vercel Preview URL | _(pending)_ |

---

## 2) Migrations المطبقة (pending)

| # | ملف | حالة |
|---|-----|------|
| 0 | preflight | ⏸ pending |
| 1 | proc-approval-1.sql | ⏸ pending |
| 2 | proc-approval-2-hardening.sql | ⏸ pending |
| 3 | proc-approval-3-matching-priority.sql | ⏸ pending |
| 4 | proc-approval-4-snapshot.sql | ⏸ pending |
| 5 | proc-approval-5-notifications-audit.sql | ⏸ pending |
| 6 | proc-approval-6-trigger-invoker.sql | ⏸ pending |
| A | proc-approval-auth-seed.sql (cloud-test) | ⏸ pending |

**Migration fixes جديدة (إن وُجدت):** _(none yet — will be numbered 7+)_

---

## 3) Auth Users التجريبية

جاهزة في `proc-approval-auth-seed.sql`:
| id | email | role | is_active |
|----|-------|------|-----------|
| 901 | requester@staging-shouon.local | employee | TRUE |
| 902 | dept_manager@staging-shouon.local | branch_manager | TRUE |
| 903 | proc_manager@staging-shouon.local | procurement_manager | TRUE |
| 904 | fin_manager@staging-shouon.local | finance_manager | TRUE |
| 905 | gen_manager@staging-shouon.local | company_manager | TRUE |
| 906 | unauthorized@staging-shouon.local | employee | TRUE |
| 907 | inactive_pm@staging-shouon.local | procurement_manager | FALSE |
| 908 | other_branch@staging-shouon.local | branch_manager (branch 902) | TRUE |

**⚠️ لا passwords حقيقية — تُضبَط عبر Dashboard → Auth → Users → password reset، أو magic link.**

---

## 4) JWT/Auth Results (pending)

سيُشغَّل `proc-approval-rls-cloud-tests.sql` بعد تطبيق seed:
| # | Actor | Action | Expected | Result |
|---|-------|--------|----------|--------|
| 1 | requester | create draft | PASS | ⏸ |
| 2 | unauthorized | create for another user | PASS (RLS block) | ⏸ |
| 3 | requester | self-approve | PASS (SELF_APPROVAL_BLOCKED) | ⏸ |
| 4 | procurement_manager | approve valid step | PASS | ⏸ |
| 5 | finance | skip step 1 | PASS (STEP_ORDER_VIOLATED) | ⏸ |
| 6 | other_branch | read another branch | PASS (RLS hides) | ⏸ |
| 7 | inactive_pm | approve | PASS (USER_INACTIVE) | ⏸ |
| 8 | anonymous | insert | PASS (RLS block) | ⏸ |
| 9 | forged JWT | submit | PASS (AUTH_REQUIRED or REQ_NOT_FOUND) | ⏸ |

---

## 5) SQL Tests Results (pending)

**النتائج المحلية (على PostgreSQL 16 isolated):** 40/40 PASS + Concurrency PASS.
**Cloud نتيجة:** ⏸ pending.

مصفوفة الاختبارات (34 اختبار + 3 bonus) موثقة في `_reengineering/local-test/PROC_APPROVAL_LOCAL_VALIDATION_REPORT.md`.

---

## 6) Concurrency Result (pending)

**النتيجة المحلية:** Session B نجحت (13ms)، Session A رُفضت بـ`STEP_NOT_PENDING`، حالة نهائية متسقة.
**Cloud نتيجة:** ⏸ pending.

---

## 7) UI Results (pending)

راجع `UI_STAGING_QUICKSTART.md` لتعليمات تشغيل الواجهة على staging.
Screenshots ستُوضع في `_reengineering/cloud-test/screenshots/procurement-approval/`.

Test cases:
- [ ] Login (كل الـ8 مستخدمين)
- [ ] Create draft (requester)
- [ ] Submit → notification يصل للـPM
- [ ] Approve step
- [ ] Reject step (سبب إلزامي)
- [ ] Snapshot يعرض القيم الأصلية للقاعدة
- [ ] Duplicate PO منع
- [ ] APPROVAL_CONFIGURATION_MISSING banner
- [ ] AMBIGUOUS_APPROVAL_RULES banner
- [ ] Desktop / Tablet / Mobile screenshots

---

## 8) Preview Deployment (pending)

**بعد نجاح Auth+RLS+UI:**
- `vercel --env-file=.env.staging.local` لإنشاء preview
- ✅ ENV vars تشير لـStaging فقط
- ❌ لا تلمس Production Vercel project

Smoke tests بعد النشر:
- [ ] login
- [ ] open procurement
- [ ] create draft
- [ ] submit
- [ ] approve
- [ ] reject
- [ ] notification
- [ ] logout

---

## 9) pg_ctl Exit Code 2 (المرحلة 11)

**الأدلة الفعلية على سلامة البيئة المحلية:**
| دليل | قيمة |
|------|-------|
| `pg_isready` بعد start | `localhost:55432 - accepting connections` |
| `psql -c "SELECT version();"` | ✅ نجح، رجع PostgreSQL 16.14 |
| تنفيذ 40+ اختبار داخل transaction | ✅ نجح كلياً |
| Concurrency test بجلستَين | ✅ نتيجة متسقة |
| `pg_ctl stop` في النهاية | ✅ `server stopped` |

**التفسير:** exit code 2 من `pg_ctl start` كان من عملية background قديمة استُبدلت بـstart لاحقة (نفس أمر مع خيارات pg_ctl مختلفة). الـcluster شغّل بالفعل — كل الأدلة أعلاه تثبت ذلك. **لا خطر متبقٍ.**

---

## 10) الأخطاء والإصلاحات (Cloud — pending)

_(سيُملأ عند التنفيذ الفعلي)_

**من الجولة المحلية (مُثبَّتة):**
- 🐛 `pg_advisory_xact_lock(bigint, bigint)` → إصلاح في migrations 2/3/4/5
- 🐛 Guard triggers كانت SECURITY DEFINER → Migration 6 (SECURITY INVOKER)
- 🐛 Migration 4 `CREATE OR REPLACE` بـreturn type مختلف → DROP FUNCTION قبل CREATE

---

## 11) الملفات الجديدة في هذه الجولة (Cloud prep)

| ملف | الغرض |
|-----|-------|
| `_reengineering/CLOUD_STAGING_BLOCKER.md` | خطوة التفويض المطلوبة |
| `_reengineering/cloud-test/apply.sh` | سكربت تطبيق آلي (يقرأ `.env.staging.local`) |
| `_reengineering/cloud-test/proc-approval-auth-seed.sql` | إنشاء auth.users + app users |
| `_reengineering/cloud-test/proc-approval-rls-cloud-tests.sql` | 9 اختبارات RLS مع JWTs حقيقية |
| `_reengineering/cloud-test/UI_STAGING_QUICKSTART.md` | تعليمات تفعيل UI على staging |
| `_reengineering/cloud-test/PROC_APPROVAL_CLOUD_STAGING_REPORT.md` | هذا التقرير |
| `.env.example` | template للـstaging config |
| `.gitignore` | تحصين لمنع تسريب `.env*` |
| `index.html.html` | آلية تبديل env عبر URL/localStorage |

---

## 12) Git Commits

_(سيُحدَّث بعد commit — راجع النهاية)_

---

## 13) المخاطر المتبقية

| # | الخطر | الشدة | التخفيف |
|---|-------|-------|---------|
| R1 | Cloud tests لم تُشغَّل | 🔴 حرج (blocks verdict) | يحل بمجرد التفويض |
| R2 | Password لـauth users غير مضبوطة | 🟡 متوسط | Admin API أو Dashboard reset |
| R3 | UI تختبر بحالات Auth حقيقية على شبكة | 🟠 متوسط | تختبر بعد التفويض |
| R4 | Vercel Functions `/api/*` بلا CORS/Bearer (خارج نطاق الموجة) | 🔴 حرج (Existing) | مذكور في `PROC_APPROVAL_REVIEW.md §G5` — يلزم قبل production |

---

## 14) Rollback على Staging

جاهز في `proc-approval-rollback.sql` — يمسح كل ما أُنشِئ من migrations 1→6.

---

## 15) Production Migration Checklist (للمرجعية فقط)

**لا تُنفَّذ إلا بعد اجتياز كل الاختبارات على Staging وموافقتك الصريحة.**

- [ ] كل tests على Staging PASS
- [ ] الواجهة اُختبِرت بيدك على Staging preview
- [ ] Auth users على Staging تعمل
- [ ] Rollback plan جاهز
- [ ] Backup لـProduction قبل التطبيق
- [ ] Downtime window محدَّد (إن لزم)
- [ ] تطبيق SQL بترتيب migrations 1→6
- [ ] Preflight بعد التطبيق (verify)
- [ ] Deploy UI إلى Production فقط بعد التحقق من SQL
- [ ] Smoke tests فوريّة post-deploy

---

## 16) الحكم النهائي

**الحالي:** `BLOCKED — SUPABASE ACCOUNT AUTHORIZATION REQUIRED`

**الأحكام المحتملة عند التنفيذ:**
- `READY FOR OWNER PREVIEW` — لو كل tests + UI PASS
- `NOT READY — CLOUD TESTS FAILED` — لو أحد الاختبارات فشل
- `BLOCKED — CLOUD PROJECT CREATION UNAVAILABLE` — لو Supabase رفض إنشاء مشروع (Free plan quota مثلاً)
